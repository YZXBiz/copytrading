import { readFileSync } from "node:fs"
import { resolve } from "node:path"
import { describe, expect, it } from "vitest"
import type { CapabilityCheck, SecretStatus } from "../../../shared/contract"
import { startFailure } from "../../../shared/start-failure"
import {
  DEFAULT_POLICY,
  type SetupDraft,
  SetupProblem,
  buildConfiguration,
  draftFromSetup,
  guruId,
  newAccount,
  newGuru,
  nextAccountName,
  profileRevision,
  typedSecrets,
} from "./draft"
import { baseUrlProblem } from "../../../shared/providers"
import { type Fraction, copiedBudget, decimal, sizing } from "./sizing"
import { type Facts, STEPS, accountStatus, discordStatus, guruStatus, keyFacts, recordChecks, resultFor, setupProgress } from "./state"
import { checkDetail, connectionProblem, stocks } from "./words"

const ready = (): SetupDraft => ({
  ...draftFromSetup(null),
  channels: "1517754775674949742, 1100000000000000002",
  discord_token: "token",
  provider: "deepseek",
  model: "deepseek-flash",
  provider_api_key: "sk-key",
  accounts: [{ ...newAccount([]), key: "k", secret: "s" }],
  gurus: [{ ...newGuru(draftFromSetup(null)), display_name: "赵哥", account_id: "primary", channel_id: "1517754775674949742", full_position_usd: "1000" }],
})

const check = (over: Partial<CapabilityCheck>): CapabilityCheck => ({
  name: "model",
  state: "failed",
  subject: null,
  environment: null,
  identity: null,
  adapter: "deepseek",
  reason_code: null,
  suggestion: null,
  symbols: [],
  ...over,
})

describe("identities match the engine", () => {
  // Digests computed with Python's json.dumps(sort_keys=True, separators=(",", ":"), ensure_ascii=False) and hashlib.
  it("derives a guru's id from its channel", async () => {
    expect(await guruId("1517754775674949742")).toBe("guru-3909e2aa")
  })

  it("derives a profile revision the way profiles.py does, with Chinese text, a quote and a newline", async () => {
    expect(await profileRevision("guru-1a2b3c4d", '赵哥 "zhao"', "买 SOXS\n卖 soxl / x")).toBe(
      "e9a88d4ef84a1c50532d3091e037c3be0c57822c3796adf2ff1c87933bee70ee",
    )
    expect(await profileRevision("guru-0", "A", "")).toBe("ad32a36d5270b600956b5d1f0b3d57562afa7c3b3f0a2ec63027b5b9d464f859")
  })
})

describe("buildConfiguration", () => {
  it("builds what the engine validates, leaving blank optionals out", async () => {
    const config = await buildConfiguration(ready())
    expect(config.version).toBe(10)
    expect(config.source).toEqual({ channel_ids: ["1517754775674949742", "1100000000000000002"], author_ids: [] })
    expect(config.provider).toEqual({ name: "deepseek", model: "deepseek-flash" })
    expect(config.routes[0]).toEqual({
      source: "discord",
      channel_id: "1517754775674949742",
      guru_id: "guru-3909e2aa",
      profile_revision: config.profiles[0]!.profile_revision,
      connections: [{ account_id: "primary", full_position_usd: "1000" }],
      repeat_window_minutes: 10,
    })
    expect(config.routes[0]).not.toHaveProperty("author_id")
  })

  it("loads a saved setup and builds it back unchanged", async () => {
    const draft = ready()
    draft.gurus[0]!.author_id = "2200000000000000009"
    draft.gurus[0]!.repeat_window_minutes = null
    draft.gurus.push({ ...newGuru(draft), display_name: "Second", channel_id: "1100000000000000002", account_id: "", full_position_usd: "" })
    draft.accounts.push({ ...newAccount(draft.accounts), key: "", secret: "" })
    draft.gurus[1]!.account_id = "account-2"
    draft.notification = { service: "discord" }
    const saved = await buildConfiguration(draft)
    expect(await buildConfiguration(draftFromSetup(saved))).toEqual(saved)
  })

  it("follows the first channel for a guru with none of its own, and the account's maximum for a blank full position", async () => {
    const draft = ready()
    draft.gurus[0]!.channel_id = ""
    draft.gurus[0]!.full_position_usd = ""
    const config = await buildConfiguration(draft)
    expect(config.routes[0]!.channel_id).toBe("1517754775674949742")
    expect(config.routes[0]!.connections[0]!.full_position_usd).toBe(DEFAULT_POLICY.max_symbol_usd)
  })

  it("trims the name and playbook before hashing, so the revision is the engine's", async () => {
    const draft = ready()
    draft.gurus[0]!.display_name = "  赵哥  "
    draft.gurus[0]!.playbook = "\n买 SOXS \n"
    const config = await buildConfiguration(draft)
    expect(config.profiles[0]).toMatchObject({ display_name: "赵哥", playbook: "买 SOXS" })
    expect(config.profiles[0]!.profile_revision).toBe(await profileRevision(config.profiles[0]!.guru_id, "赵哥", "买 SOXS"))
  })

  const refuses = async (change: (d: SetupDraft) => void, message: RegExp | string) => {
    const draft = ready()
    change(draft)
    await expect(buildConfiguration(draft)).rejects.toThrow(SetupProblem)
    await expect(buildConfiguration(draft)).rejects.toThrow(message)
  }

  it("says what is missing, in the owner's words", async () => {
    await refuses((d) => (d.channels = " , "), "Enter at least one Discord channel ID")
    await refuses((d) => (d.model = " "), "Enter a model name")
    await refuses((d) => ((d.provider = "openai_compatible"), (d.base_url = "")), "Enter the base URL your model is served at.")
    await refuses((d) => (d.accounts = []), "Add a broker account")
    await refuses((d) => (d.gurus = []), "Add a guru to copy")
    await refuses((d) => (d.accounts[0]!.name = "my account"), "may only use letters, digits")
    await refuses((d) => (d.gurus[0]!.display_name = " "), "Each guru needs a name.")
    await refuses((d) => (d.gurus[0]!.channel_id = "999"), "not listed under Discord")
    await refuses((d) => (d.gurus[0]!.account_id = ""), "needs an account to copy into")
    await refuses((d) => (d.gurus[0]!.account_id = "other"), "isn't one of your broker accounts")
    await refuses((d) => (d.gurus[0]!.full_position_usd = "0"), "full position")
    await refuses((d) => (d.gurus[0]!.playbook = "x".repeat(8001)), "playbook under 8,000 characters")
  })

  it("refuses an account two gurus copy into, and a channel two gurus read", async () => {
    const twice = ready()
    twice.gurus.push({ ...twice.gurus[0]!, uid: "b", display_name: "B", channel_id: "1100000000000000002" })
    await expect(buildConfiguration(twice)).rejects.toThrow("already copies “赵哥”. Each account copies one guru.")
    const sharing = ready()
    sharing.accounts.push({ ...newAccount(sharing.accounts) })
    sharing.gurus.push({ ...sharing.gurus[0]!, uid: "b", display_name: "B", account_id: "account-2" })
    await expect(sharing.gurus.length && buildConfiguration(sharing)).rejects.toThrow("both read channel")
  })

  it("keeps an Ollama address only for a provider that takes one", async () => {
    const draft = ready()
    draft.provider = "ollama"
    draft.base_url = "http://localhost:11434"
    expect((await buildConfiguration(draft)).provider.base_url).toBe("http://localhost:11434")
    draft.provider = "openai"
    draft.base_url = ""
    expect((await buildConfiguration(draft)).provider).not.toHaveProperty("base_url")
  })
})

describe("setup helpers", () => {
  it("names the next account", () => {
    expect(nextAccountName([])).toBe("primary")
    expect(nextAccountName([{ ...newAccount([]), name: "primary" }])).toBe("account-2")
    expect(nextAccountName([{ ...newAccount([]), name: "primary" }, { ...newAccount([]), name: "account-2" }])).toBe("account-3")
  })

  it("accepts https anywhere and http only on this Mac", () => {
    expect(baseUrlProblem("ollama", "http://localhost:11434")).toBeNull()
    expect(baseUrlProblem("ollama", "http://[::1]:11434")).toBeNull()
    expect(baseUrlProblem("openai_compatible", "https://api.example.com/v1")).toBeNull()
    expect(baseUrlProblem("openai_compatible", "http://example.com")).toMatch(/must start with https/)
    expect(baseUrlProblem("openai_compatible", "https://user:pw@example.com")).toMatch(/must start with https/)
    expect(baseUrlProblem("openai", "https://x.com")).toBe("openai is served at a fixed address.")
    expect(baseUrlProblem("openai", "")).toBeNull()
  })

  it("sends only keys the owner typed in full", () => {
    const draft = ready()
    expect(typedSecrets(draft)).toEqual({
      discord_token: "token",
      provider_api_key: "sk-key",
      brokers: [{ account_id: "primary", key: "k", secret: "s" }],
    })
    draft.accounts[0]!.secret = ""
    expect(typedSecrets(draft)?.brokers).toBeUndefined()
    expect(typedSecrets({ ...ready(), discord_token: "", provider_api_key: "", accounts: [] })).toBeNull()
  })
})

describe("sizing", () => {
  const examples = JSON.parse(readFileSync(resolve(__dirname, "../../../../app/Resources/Contracts/sizing-examples.json"), "utf8")).examples as {
    case: string
    full_position_usd: string
    fraction: { numerator: number; denominator: number } | null
    budget_usd: string
    max_order_usd?: string
    spent_usd?: string
  }[]

  it.each(examples)("gives the shared example: $case", (example) => {
    const fraction: Fraction | null = example.fraction && { numerator: BigInt(example.fraction.numerator), denominator: BigInt(example.fraction.denominator) }
    const asked = copiedBudget(example.full_position_usd, fraction, example.max_order_usd ?? null)
    expect(asked && decimal(asked)).toBe(example.budget_usd)
    if (example.max_order_usd && asked) {
      const cap = copiedBudget("1000000", null, example.max_order_usd)!
      expect(Number(decimal(asked < cap ? asked : cap))).toBe(Number(example.spent_usd))
    }
  })

  it("shows what a 1/6, a 1/2 and an unsized call buy, cut to the largest single buy", () => {
    const result = sizing("1000", { ...DEFAULT_POLICY, max_order_usd: "100", max_symbol_usd: "600" })!
    expect(result.figures).toEqual([
      { label: "A 1/6 call", amount: "$100", cutFrom: "$166.66" },
      { label: "A 1/2 call", amount: "$100", cutFrom: "$500" },
      { label: "No size given", amount: "$100", cutFrom: null },
    ])
    expect(result.note).toBe("Your largest single buy, $100, caps any one buy.")
    expect(result.warning).toBe("Above this account's $600 limit for one stock: buys stop there.")
  })

  it("shows nothing until the guru has a full position", () => {
    expect(sizing("", { ...DEFAULT_POLICY, max_symbol_usd: "" })).toBeNull()
    expect(sizing("abc", DEFAULT_POLICY)).toBeNull()
  })
})

describe("words", () => {
  it("words a failed check as ConnectionProblem does", () => {
    expect(connectionProblem(check({ reason_code: "model_key_rejected" }))).toBe("DeepSeek didn't accept the API key.")
    expect(connectionProblem(check({ reason_code: "model_not_found" }), " deepseek-x ")).toBe("DeepSeek has no model called “deepseek-x”.")
    expect(connectionProblem(check({ reason_code: "model_unreachable", adapter: "ollama" }))).toBe(
      "Nothing answered at that address. Check the Base URL and that Ollama is running.",
    )
    expect(connectionProblem(check({ name: "broker", reason_code: "broker_keys_are_live", adapter: "alpaca" }))).toMatch(/These are live keys/)
    expect(connectionProblem(check({ reason_code: "something_new" }))).toBe("Couldn't check this connection. Try again in a moment.")
    expect(connectionProblem(check({ name: "configuration", subject: "primary", reason_code: "removed_account_has_open_orders", symbols: ["A", "B", "C", "D", "E"] }))).toBe(
      "primary still has orders for A, B, C and 2 more that CopyTrading placed. Let them fill or cancel them in Alpaca, or keep primary in the setup.",
    )
    expect(stocks(["GFS", "NVDA"])).toBe("GFS and NVDA")
  })

  it("never shows the engine's raw identity", () => {
    expect(checkDetail(check({ state: "ready", name: "model", identity: "deepseek:deepseek-flash" }))).toBe("DeepSeek answered as deepseek-flash")
    expect(checkDetail(check({ state: "ready", name: "broker", environment: "paper", identity: "PA123" }))).toBe("Alpaca paper account found")
    expect(checkDetail(check({ state: "ready", name: "source", identity: "user#1" }))).toBe("Signed in to Discord")
  })

  it("words a start that did not take: accounts by name first, then the service", () => {
    expect(startFailure("accounts_unavailable", [{ id: "a", state: "failed", error_code: "broker_keys_rejected" }], "DeepSeek")).toBe(
      "a didn't open: Alpaca didn't accept its API keys. Paste them again from your Alpaca dashboard.",
    )
    expect(
      startFailure(null, [{ id: "a", state: "failed", error_code: "alpaca_account_shared" }, { id: "b", state: "failed", error_code: "alpaca_account_shared" }], "x"),
    ).toMatch(/^a and b use keys for the same Alpaca account/)
    expect(startFailure("provider_unavailable", [], "DeepSeek")).toBe("DeepSeek couldn't be reached. Check your internet connection and its API key, then start again.")
    expect(startFailure("some_code", [], "x")).toBe("Some code. Start again.")
  })
})

describe("progress and status", () => {
  const none: SecretStatus = { discord_token: false, provider_api_key: false, notification_token: false, brokers: {} }
  const facts = (draft: SetupDraft, secrets: SecretStatus = none) => keyFacts(secrets, null, draft)

  it("ticks each step as it is filled in and points at the first one left", () => {
    const empty = draftFromSetup(null)
    expect(setupProgress(empty, facts(empty), false).next).toBe("discord")
    const draft = ready()
    const progress = setupProgress(draft, facts(draft), false)
    expect([...progress.done]).toEqual(["discord", "interpreter", "account", "guru"])
    expect(progress.isReadyToCheck).toBe(true)
    expect(progress.next).toBe("start")
    expect(STEPS).toHaveLength(5)
  })

  it("counts saved keys, but a failed check keeps its step from ticking", () => {
    const draft = { ...ready(), discord_token: "", provider_api_key: "", accounts: [{ ...ready().accounts[0]!, key: "", secret: "" }] }
    const saved: SecretStatus = { discord_token: true, provider_api_key: true, notification_token: false, brokers: { primary: true } }
    // The saved model key only counts for the provider it was saved for.
    expect(setupProgress(draft, { discord: true, providerKey: false, brokers: saved.brokers }, false).done.has("interpreter")).toBe(false)
    expect(setupProgress(draft, { discord: true, providerKey: true, brokers: saved.brokers }, false).done.has("interpreter")).toBe(true)
    expect(setupProgress(draft, { discord: true, providerKey: true, brokers: saved.brokers }, false, new Set(["discord"])).done.has("discord")).toBe(false)
  })

  it("keeps a check only while what it checked is unchanged", () => {
    const draft = ready()
    const checks = recordChecks(draft, [check({ name: "source", state: "ready" })])
    expect(resultFor(checks, draft, "discord")?.check?.state).toBe("ready")
    expect(resultFor(checks, { ...draft, discord_token: "new" }, "discord")).toBeUndefined()
    expect(resultFor(checks, { ...draft, channels: "1" }, "discord")).toBeUndefined()
  })

  it("reads each row's status: needs keys, checked, saved, copying", async () => {
    const draft = ready()
    const built = await buildConfiguration(draft)
    const base: Facts = { draft, saved: null, built, keys: facts(draft), trading: null, checks: {} }
    expect(accountStatus({ ...base, draft: { ...draft } }, { ...draft.accounts[0]!, key: "", secret: "" })).toEqual({ text: "Needs keys", tone: "caution" })
    expect(accountStatus(base, draft.accounts[0]!)).toEqual({ text: "Not saved yet", tone: "inactive" })
    expect(accountStatus(base, { ...draft.accounts[0]!, name: "bad name" })).toEqual({ text: "Needs a valid name", tone: "caution" })
    const checks = recordChecks(draft, [check({ name: "source", state: "failed", reason_code: "source_probe_timed_out" })])
    expect(discordStatus({ ...base, checks })).toEqual({ text: "Couldn't connect", tone: "caution" })
    expect(guruStatus(base, draft.gurus[0]!)).toEqual({ text: "Not saved yet", tone: "inactive" })

    const savedDraft = { ...draft, discord_token: "", provider_api_key: "", accounts: [{ ...draft.accounts[0]!, key: "", secret: "" }] }
    const saved: Facts = {
      draft: savedDraft,
      saved: built,
      built,
      keys: { discord: true, providerKey: true, brokers: { primary: true } },
      trading: { state: "running", configured_accounts: 1, active_accounts: 1, source_connected: true, model_ready: false, error_code: null },
      checks: {},
    }
    expect(guruStatus(saved, savedDraft.gurus[0]!)).toEqual({ text: "Copying", tone: "positive" })
    expect(discordStatus(saved)).toEqual({ text: "Connected", tone: "positive" })
    expect(accountStatus(saved, savedDraft.accounts[0]!)).toEqual({ text: "Connected", tone: "positive" })
  })
})
