import { beforeEach, describe, expect, it, vi } from "vitest"
import type { CapabilityCheck, Result, SetupView, TradingConfiguration } from "../../../shared/contract"
import { buildConfiguration, draftFromSetup, newAccount, newGuru } from "./draft"
import { addAccount, applyLimits, connect, discard, edit, editAccount, learnPlaybook, pickProvider, refreshStatus, reload, setupState, startCopying } from "./setup-store"

// The store talks to main through window.copytrading; each test gives it a fake and reads what it was asked, in order.

const ok = <T>(value: T): Result<T> => ({ ok: true, value })
const check = (over: Partial<CapabilityCheck> = {}): CapabilityCheck => ({
  name: "source", state: "ready", subject: null, environment: null, identity: "user", adapter: "discord",
  reason_code: null, suggestion: null, symbols: [], ...over,
})

async function savedSetup(): Promise<SetupView> {
  const draft = draftFromSetup(null)
  draft.channels = "1100000000000000001"
  draft.provider = "deepseek"
  draft.model = "deepseek-flash"
  draft.accounts = [{ ...newAccount([]), name: "zhap" }]
  draft.gurus = [{ ...newGuru(draft), display_name: "Zhao", account_id: "zhap", full_position_usd: "1000" }]
  return { configuration: await buildConfiguration(draft), revision: "a".repeat(64), keys_present: true, pending_activation: null }
}

function install(saved: SetupView | null, overrides: { act?: Record<string, unknown>; read?: Record<string, unknown>; secrets?: object } = {}) {
  const calls: string[] = []
  const log = (name: string, value: unknown) => async (...args: unknown[]) => {
    calls.push(name)
    return typeof value === "function" ? (value as (...a: unknown[]) => unknown)(...args) : value
  }
  const secrets = { discord_token: true, provider_api_key: true, notification_token: false, brokers: { zhap: true }, ...overrides.secrets }
  const act = {
    setSecrets: log("setSecrets", ok(secrets)),
    checkConnection: log("checkConnection", ok(check())),
    validateTrading: log("validateTrading", ok({ report: { configuration_revision: "b".repeat(64), activatable: true, checks: [], cost_notice: "" }, activation_token: "tok" })),
    saveSetup: log("saveSetup", ok(null)),
    startTrading: log("startTrading", ok({ state: "running" })),
    controlAccount: log("controlAccount", ok({})),
    updateAccountLimits: log("updateAccountLimits", ok({ revision: "c".repeat(64) })),
    learnGuruPlaybook: log("learnGuruPlaybook", ok({ posts_read: 12, playbook: "买 X", summary: "Short calls.", provider: "deepseek", model: "deepseek-flash", cost_notice: "" })),
    ...overrides.act,
  }
  const read = {
    getSetup: log("getSetup", ok(saved)),
    getSecretStatus: log("getSecretStatus", ok(secrets)),
    getStatus: log("getStatus", ok({ state: "paused", configured_accounts: 1, active_accounts: 0, source_connected: false, model_ready: false, error_code: null })),
    getAccounts: log("getAccounts", ok({ items: [{ account_id: "zhap", active_configuration: true, entry_permission: "paused" }], unavailable_accounts: [] })),
    ...overrides.read,
  }
  vi.stubGlobal("window", { copytrading: { act, read } })
  return { calls, act }
}

beforeEach(() => {
  vi.unstubAllGlobals()
})

describe("connect", () => {
  it("saves the typed key, then checks, and keeps the answer only while the fields are unchanged", async () => {
    const { calls } = install(null, { secrets: { discord_token: false } })
    await reload()
    edit((d) => ({ ...d, channels: "1100000000000000001", discord_token: "typed-token" }))
    await connect("discord")
    expect(calls.filter((c) => c === "setSecrets" || c === "checkConnection")).toEqual(["setSecrets", "checkConnection"])
    expect(setupState().checks.discord?.check?.state).toBe("ready")
  })

  it("says what is missing instead of checking", async () => {
    const { calls } = install(null, { secrets: { discord_token: false, provider_api_key: false } })
    await reload()
    await connect("discord")
    expect(setupState().notices.discord).toBe("Enter a channel ID and your Discord token to connect.")
    expect(calls).not.toContain("checkConnection")
    edit((d) => ({ ...d, model: "m", provider: "openai" }))
    await connect("interpreter")
    expect(setupState().notices.interpreter).toBe("Enter the API key to connect.")
  })

  it("refuses half a pair of broker keys", async () => {
    install(null, { secrets: { brokers: {} } })
    await reload()
    edit((d) => ({ ...d, accounts: [{ ...newAccount([]), key: "k" }] }))
    await connect("account:primary")
    expect(setupState().notices["account:primary"]).toBe("Enter both the API key and the secret to connect.")
  })

  it("reads a check the engine could not run as a failure with the reason", async () => {
    install(await savedSetup(), { act: { checkConnection: async () => ({ ok: false, error: "No keys are saved for zhap." }) } })
    await reload()
    await connect("account:zhap")
    expect(setupState().checks["account:zhap"]).toMatchObject({ check: { state: "failed" }, error: "No keys are saved for zhap." })
  })
})

describe("pickProvider", () => {
  it("empties the key and shows the new provider's model, unless the owner typed one", async () => {
    install(null)
    await reload()
    edit((d) => ({ ...d, provider: "anthropic", provider_api_key: "sk-a", model: "" }))
    pickProvider("deepseek")
    expect(setupState().draft).toMatchObject({ provider: "deepseek", provider_api_key: "", model: "deepseek-flash" })
    edit((d) => ({ ...d, model: "my-own" }))
    pickProvider("openai")
    expect(setupState().draft.model).toBe("my-own")
  })

  it("keeps the key when the same provider is picked again", async () => {
    install(null)
    await reload()
    edit((d) => ({ ...d, provider: "openai", provider_api_key: "sk-keep", model: "gpt" }))
    pickProvider("openai")
    expect(setupState().draft.provider_api_key).toBe("sk-keep")
  })
})

describe("startCopying", () => {
  async function ready(saved: SetupView | null, overrides = {}) {
    const fake = install(saved, overrides)
    await reload()
    discard()
    await reload()
    return fake
  }

  it("checks, saves exactly what was checked, then starts, and names an account still not buying", async () => {
    const saved = await savedSetup()
    const { calls } = await ready(saved)
    calls.length = 0
    edit((d) => ({ ...d, model: "deepseek-chat" }))
    await startCopying()
    expect(calls.slice(0, 4)).toEqual(["validateTrading", "saveSetup", "startTrading", "getSetup"])
    // Main turns the accounts on; the page only reports one the engine still holds with buys off.
    expect(calls).not.toContain("controlAccount")
    expect(setupState().start).toEqual({ phase: "started", paused: ["zhap"] })
  })

  it("reports every account buying as plainly started", async () => {
    await ready(await savedSetup(), {
      read: { getAccounts: async () => ok({ items: [{ account_id: "zhap", active_configuration: true, entry_permission: "enabled" }], unavailable_accounts: [] }) },
    })
    await startCopying()
    expect(setupState().start).toEqual({ phase: "started", paused: [] })
  })

  it("sends the validation's revision and token on, and a fresh activation id", async () => {
    const seen: Record<string, unknown>[] = []
    await ready(await savedSetup(), {
      act: {
        saveSetup: async (p: unknown) => (seen.push(p as Record<string, unknown>), ok(null)),
        startTrading: async (p: unknown) => (seen.push(p as Record<string, unknown>), ok({ state: "running" })),
      },
    })
    await startCopying()
    expect(seen[0]).toMatchObject({ revision: "b".repeat(64) })
    expect(seen[1]).toMatchObject({ validation_token: "tok", activation_id: expect.stringMatching(/^[0-9a-f-]{36}$/) })
  })

  it("saves and starts nothing when a connection fails, and shows the checks", async () => {
    const report = { configuration_revision: "b".repeat(64), activatable: false, cost_notice: "", checks: [check({ state: "failed", reason_code: "source_probe_timed_out" })] }
    const { calls } = await ready(await savedSetup(), { act: { validateTrading: async () => ok({ report, activation_token: null }) } })
    calls.length = 0
    await startCopying()
    expect(calls).not.toContain("saveSetup")
    expect(calls).not.toContain("startTrading")
    expect(setupState().start).toMatchObject({ phase: "failed", message: "Some connections need attention. Nothing was saved.", report })
    expect(setupState().checks.discord?.check?.state).toBe("failed")
  })

  it("shows nothing when the owner says no in the native dialog", async () => {
    await ready(await savedSetup(), { act: { startTrading: async () => ({ ok: false, error: "Cancelled.", cancelled: true }) } })
    await startCopying()
    expect(setupState().start.phase).toBe("idle")
  })

  it("says why a start did not take, in main's words", async () => {
    await ready(await savedSetup(), { act: { startTrading: async () => ({ ok: false, error: "Copying didn't start. Discord couldn't be reached." }) } })
    await startCopying()
    expect(setupState().start).toMatchObject({ phase: "failed", message: "Copying didn't start. Discord couldn't be reached." })
  })

  describe("a start the engine has not confirmed", () => {
    const record = (over: Record<string, unknown>) => ({
      requested_activation_id: "", activation_id: null, candidate_revision: null, committed_revision: null, committed_activation_id: null,
      phase: "starting", runtime_state: "starting", error_code: null, ...over,
    })

    async function pendingStart(activation: () => Record<string, unknown>) {
      const saved = await savedSetup()
      const pending = { ...saved, pending_activation: { activation_id: "x", candidate_revision: "b".repeat(64) } }
      const stillPending = { on: false }
      await ready(saved, {
        read: {
          getSetup: async () => ok(stillPending.on ? pending : saved),
          getTradingActivation: async () => ok(record(activation())),
          getStatus: async () => ok({ state: "paused", configured_accounts: 1, active_accounts: 0, source_connected: false, model_ready: false, error_code: null, accounts: [{ id: "zhap", state: "failed", error_code: "broker_keys_rejected" }] }),
        },
      })
      stillPending.on = true
      await startCopying()
      expect(setupState().start).toMatchObject({ phase: "pending" })
      return stillPending
    }

    it("stays pending while the engine is still committing it", async () => {
      await pendingStart(() => ({}))
      await refreshStatus()
      expect(setupState().start.phase).toBe("pending")
    })

    it("becomes started once the engine committed it", async () => {
      const flag = await pendingStart(() => ({ phase: "ready", runtime_state: "running" }))
      flag.on = false
      await refreshStatus()
      expect(setupState().start.phase).toBe("started")
    })

    it("becomes not started, with the account named, once the engine stopped without committing it", async () => {
      const flag = await pendingStart(() => ({ phase: "failed", runtime_state: "paused" }))
      flag.on = false
      await refreshStatus()
      expect(setupState().start).toMatchObject({
        phase: "failed",
        message: "The new setup didn't start. zhap didn't open: Alpaca didn't accept its API keys. Paste them again from your Alpaca dashboard.",
      })
    })
  })

  it("will not start without a Discord token, or with half a broker key", async () => {
    const { calls } = await ready(await savedSetup(), { secrets: { discord_token: false } })
    calls.length = 0
    await startCopying()
    expect(setupState().start).toMatchObject({ phase: "failed", message: "Enter your Discord token in Connections first." })
    expect(calls).toEqual([])
    edit((d) => ({ ...d, discord_token: "t", accounts: d.accounts.map((a) => ({ ...a, key: "k" })) }))
    await startCopying()
    expect(setupState().start).toMatchObject({ message: "Enter both the API key and the secret for “zhap”." })
  })

  it("says what is wrong with the form before asking the engine anything", async () => {
    const { calls } = await ready(await savedSetup())
    calls.length = 0
    edit((d) => ({ ...d, gurus: d.gurus.map((g) => ({ ...g, display_name: " " })) }))
    await startCopying()
    expect(setupState().start).toMatchObject({ message: "Each guru needs a name." })
    expect(calls).toEqual([])
  })
})

describe("accounts and limits", () => {
  it("points the first guru with no account at a new account, and follows a rename", async () => {
    install(null)
    await reload()
    edit((d) => ({ ...d, gurus: [newGuru(d)] }))
    const uid = addAccount()
    expect(setupState().draft.gurus[0]!.account_id).toBe("primary")
    editAccount(uid, (a) => ({ ...a, name: "paper-1" }))
    expect(setupState().draft.gurus[0]!.account_id).toBe("paper-1")
  })

  it("applies one account's limits to the saved setup, and nothing else", async () => {
    const saved = await savedSetup()
    const sent: unknown[] = []
    install(saved, { act: { updateAccountLimits: async (p: unknown) => (sent.push(p), ok({ revision: "c".repeat(64) })) } })
    await reload()
    edit((d) => ({ ...d, model: "edited-but-not-a-limit", accounts: d.accounts.map((a) => ({ ...a, policy: { ...a.policy, max_order_usd: "250" } })) }))
    expect(await applyLimits(setupState().draft.accounts[0]!.uid)).toBeNull()
    const sentConfig = (sent[0] as { configuration: TradingConfiguration }).configuration
    expect(sentConfig.accounts[0]!.policy.max_order_usd).toBe("250")
    expect(sentConfig.provider.model).toBe("deepseek-flash")
  })

  it("returns main's reason when limits cannot be applied, and nothing when the owner declines", async () => {
    const saved = await savedSetup()
    install(saved, { act: { updateAccountLimits: async () => ({ ok: false, error: "Only account limits can change while copying." }) } })
    await reload()
    expect(await applyLimits(setupState().draft.accounts[0]!.uid)).toBe("Only account limits can change while copying.")
    install(saved, { act: { updateAccountLimits: async () => ({ ok: false, error: "Cancelled.", cancelled: true }) } })
    expect(await applyLimits(setupState().draft.accounts[0]!.uid)).toBeNull()
  })
})

describe("learnPlaybook", () => {
  it("saves the typed keys, drafts the playbook, and says what it read", async () => {
    const saved = await savedSetup()
    const { calls } = install(saved, { secrets: { discord_token: false, provider_api_key: false } })
    await reload()
    edit((d) => ({ ...d, discord_token: "t", provider: "deepseek", provider_api_key: "k" }))
    const result = await learnPlaybook(setupState().draft.gurus[0]!.uid)
    expect(calls.filter((c) => c === "setSecrets" || c === "learnGuruPlaybook")).toEqual(["setSecrets", "setSecrets", "learnGuruPlaybook"])
    expect(result).toEqual({ ok: true, text: "Read 12 posts with deepseek-flash. Short calls. The playbook is drafted; read it over before you start copying." })
    expect(setupState().draft.gurus[0]!.playbook).toBe("买 X")
  })

  it("asks for the Discord token and key first", async () => {
    install(await savedSetup(), { secrets: { discord_token: false } })
    await reload()
    expect((await learnPlaybook(setupState().draft.gurus[0]!.uid)).ok).toBe(false)
  })
})
