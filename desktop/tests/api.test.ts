import { copyFileSync, mkdtempSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { type Engine, createApi } from "../electron/main/api"
import { EngineError } from "../electron/main/engine/bridge"
import { SecretStore, redactState } from "../electron/main/secrets"
import { SETUP_FILE, SetupFile } from "../electron/main/setup-file"

const FIXTURE = join(__dirname, "fixtures", SETUP_FILE)
const saved = JSON.parse(readFileSync(FIXTURE, "utf8"))
const dirs: string[] = []
afterEach(() => dirs.splice(0).forEach((dir) => rmSync(dir, { recursive: true, force: true })))

// A cipher that is reversible but not the identity, so a test can see the file is not plain text.
const cipher = { encrypt: (text: string) => Buffer.from(text).reverse(), decrypt: (data: Buffer) => Buffer.from(data).reverse().toString() }

const DISCORD = "SENTINEL-discord-token-0001"
const PROVIDER = "SENTINEL-provider-key-0002"
const BROKER_KEY = "SENTINEL-alpaca-key-0003"
const BROKER_SECRET = "SENTINEL-alpaca-secret-0004"

const plan = (side: string, qty: string, symbol: string, limit: string | null) => ({
  side, qty, symbol, limit_price: limit, type: "limit", position_intent: "x", source_price: "1", entry_tolerance_pct: "0", lot_id: null,
  entry_price: "1", session: "regular", requested_usd: null, budget_usd: null, limited_by: null,
})

const MUTATING = [
  "confirm_manual_orders", "confirm_lot_sale", "start_trading", "pause_trading", "control_account",
  "approve_proposal", "delete_account_record", "complete_restore_candidate", "update_account_limits",
]

/** The saved setup with the first account's limits changed. */
function withLimits(changes: Record<string, unknown>) {
  const config = structuredClone(saved.configuration)
  Object.assign(config.accounts[0].policy, changes)
  return config
}

function harness(answer = true, whileAsking: () => Promise<unknown> = async () => {}) {
  const requests: { op: string; params: Record<string, unknown> }[] = []
  const replies: Record<string, (params: Record<string, unknown>) => unknown> = {
    get_trading_status: () => ({ type: "trading_status", trading: { state: "paused" } }),
    preview_lot_sale: (p) => ({
      type: "lot_sale_preview",
      preview: { request: p.preview, symbol: "SOXS", plan: plan("sell", "2.052463", "SOXS", "40.45") },
    }),
    preview_manual_order: (p) => ({
      type: "manual_preview",
      preview: { request: p.preview, plan: plan("buy", "10", "F", "12.30") },
    }),
    list_proposals: () => ({
      type: "proposals",
      proposals: [
        { proposal_id: "p-0123456789ab", state: "pending", digest: "d".repeat(64), subject: { kind: "resume_account", account_id: "zhap-account-2" } },
      ],
    }),
    restore_candidate_status: () => ({
      type: "restore_candidate_status",
      candidate: { candidate_id: "cand-1", account_ids: ["zhap-account-2"] },
    }),
  }
  const engine: Engine = {
    request: async (op, params = {}) => {
      requests.push({ op, params })
      return replies[op]?.(params) ?? { type: "ok", sale: {}, commands: {}, trading: {}, control: {}, proposal: {} }
    },
  }
  const dir = mkdtempSync(join(tmpdir(), "api-"))
  dirs.push(dir)
  copyFileSync(FIXTURE, join(dir, SETUP_FILE))
  const secrets = new SecretStore(join(dir, "secrets.bin"), cipher)
  const asked: string[] = []
  const setup = new SetupFile(dir)
  const api = createApi({
    engine,
    setup,
    secrets,
    activation: { looks: 2, waitMs: 0 },
    confirm: async (text) => {
      asked.push(text)
      await whileAsking()
      return answer
    },
  })
  return { api, setup, secrets, requests, asked, replies, dir, sent: (op: string) => requests.filter((r) => r.op === op) }
}

type Harness = ReturnType<typeof harness>

const ACTIVATION = "9d3f2c1a-0000-4000-8000-000000000001"
const START = { activation_id: ACTIVATION, validation_token: "t" }
const lotSale = { sale: { command_id: "c-1", preview_id: "pv-1", account_id: "zhap-account-2", actor: "owner" } }
const order = { commands: [{ command_id: "c-2", preview_id: "pv-2", account_id: "zhap-account-2", actor: "owner" }] }

/** Each confirmed action: how to set it up, what to send, and the engine operation it must not reach unasked. */
const CONFIRMED: [string, string, (h: Harness) => Promise<unknown>, Record<string, unknown> | undefined, string][] = [
  [
    "confirmLotSale", "confirm_lot_sale",
    (h) => h.api.read("previewLotSale", { preview: { preview_id: "pv-1", account_id: "zhap-account-2", lot_id: "lot-1", qty: "2.052463" } }),
    lotSale, "Sell 2.052463 SOXS at $40.45 or better from zhap-account-2?",
  ],
  [
    "confirmManualOrders", "confirm_manual_orders",
    (h) => h.api.read("previewManualOrder", { preview: { preview_id: "pv-2", account_id: "zhap-account-2", correction_id: "k", instruction_index: 0 } }),
    order, "Buy 10 F at $12.30 or better in zhap-account-2?",
  ],
  [
    "startTrading", "start_trading",
    async (h) => {
      h.secrets.setRevision(saved.secretRevision)
      h.secrets.merge({ discord_token: DISCORD })
    },
    { activation_id: "9d3f2c1a-0000-4000-8000-000000000001", validation_token: "t" },
    "Start copying?\n\n赵哥 into zhap-account-2 (paper)\nStandard stock alerts into zhap-account-2 (paper) and zhap-account-3 (paper)\n\nThis places paper orders.",
  ],
  [
    "updateAccountLimits", "update_account_limits",
    async (h) => {
      h.replies.update_account_limits = () => ({ type: "account_limits", revision: "a".repeat(64) })
    },
    { configuration: withLimits({ max_order_usd: "250", approve_orders: true }) },
    "Change copying limits now?\n\nzhap-account-2: Each order $100 → $250; Approve each order off → on\n\nCopying uses them from the next post.",
  ],
  ["pauseTrading", "pause_trading", async () => {}, undefined, "Pause copying? No new posts are copied until you start again."],
  [
    "controlAccount", "control_account", async () => {},
    { command: { command_id: "c-3", account_id: "zhap-account-2", action: "pause" } },
    "Pause copying into zhap-account-2? New posts are not copied into it until you resume it.",
  ],
  ["approveProposal", "approve_proposal", async () => {}, { proposal_id: "p-0123456789ab", digest: "x".repeat(64) }, "Resume copying into zhap-account-2?"],
  [
    "deleteAccountRecord", "delete_account_record", async () => {}, { account_id: "zhap-account-3" },
    "Delete the record of zhap-account-3? Its shares stay at Alpaca; only this app's record of them goes.",
  ],
  [
    "completeRestoreCandidate", "complete_restore_candidate", async () => {},
    { candidate_id: "cand-1", completion_token: "e".repeat(32) },
    "Replace this Mac's CopyTrading records with the backup (zhap-account-2)?",
  ],
]

describe("confirmation gate", () => {
  it("covers every action that moves money or changes copying", () => {
    expect(CONFIRMED.map((c) => c[1]).sort()).toEqual([...MUTATING].sort())
  })

  it.each(CONFIRMED)("%s: a No reaches no engine operation that changes anything", async (name, _op, setup, params) => {
    const h = harness(false)
    await setup(h)
    const result = await h.api.act(name, params)
    expect(result).toEqual({ ok: false, error: "Cancelled.", cancelled: true })
    expect(h.asked).toHaveLength(1)
    expect(h.requests.filter((r) => MUTATING.includes(r.op))).toEqual([])
  })

  it.each(CONFIRMED)("%s: a Yes sends it once, after asking exactly what it will do", async (name, op, setup, params, text) => {
    const h = harness(true)
    await setup(h)
    const result = await h.api.act(name, params)
    expect(result).toMatchObject({ ok: true })
    expect(h.asked).toEqual([text])
    expect(h.sent(op)).toHaveLength(1)
  })

  it("refuses to confirm an order the engine never previewed, without asking or sending", async () => {
    const h = harness(true)
    const result = await h.api.act("confirmLotSale", lotSale)
    expect(result).toMatchObject({ ok: false, error: expect.stringContaining("not previewed") })
    expect(h.asked).toEqual([])
    expect(h.requests).toEqual([])
  })

  it("refuses to confirm a preview against another account", async () => {
    const h = harness(true)
    await h.api.read("previewLotSale", { preview: { preview_id: "pv-1", account_id: "zhap-account-2", lot_id: "lot-1", qty: "1" } })
    const result = await h.api.act("confirmLotSale", { sale: { ...lotSale.sale, account_id: "zhap-account-3" } })
    expect(result).toMatchObject({ ok: false, error: expect.stringContaining("different account") })
    expect(h.sent("confirm_lot_sale")).toEqual([])
  })

  it("sends the digest the engine holds for a proposal, never the page's", async () => {
    const h = harness(true)
    await h.api.act("approveProposal", { proposal_id: "p-0123456789ab", digest: "x".repeat(64) })
    expect(h.sent("approve_proposal")[0]!.params).toEqual({ proposal_id: "p-0123456789ab", digest: "d".repeat(64) })
  })

  it("starts the saved setup, not a setup the page sends", async () => {
    const h = harness(true)
    h.secrets.setRevision(saved.secretRevision)
    h.secrets.merge({ discord_token: DISCORD })
    await h.api.act("startTrading", { ...START, configuration: { version: 10, routes: [] } })
    expect(h.sent("start_trading")[0]!.params.configuration).toEqual(saved.configuration)
  })

  it("starts nothing if the page saves another setup while the dialog is open, and never sends another key", async () => {
    const during: unknown[] = []
    let h: Harness
    h = harness(true, async () => {
      during.push(await h.api.act("saveSetup", { configuration: withLimits({ max_order_usd: "9999" }), revision: "f".repeat(64) }))
      during.push(await h.api.act("setSecrets", { discord_token: "SENTINEL-swapped-token-9999" }))
    })
    h.secrets.setRevision(saved.secretRevision)
    h.secrets.merge({ discord_token: DISCORD })
    const result = await h.api.act("startTrading", START)
    expect(during).toMatchObject([{ ok: true }, { ok: true }]) // the page really did change both mid-dialog
    expect(result).toMatchObject({ ok: false, error: expect.stringContaining("changed while you were confirming") })
    expect(h.sent("start_trading")).toEqual([])
  })

  it("refuses to change limits if the saved setup changed while the dialog was open", async () => {
    let h: Harness
    h = harness(true, async () => {
      await h.api.act("saveSetup", { configuration: withLimits({ max_symbol_usd: "700" }), revision: "f".repeat(64) })
    })
    h.replies.update_account_limits = () => ({ type: "account_limits", revision: "a".repeat(64) })
    const result = await h.api.act("updateAccountLimits", { configuration: withLimits({ max_order_usd: "250" }) })
    expect(result).toMatchObject({ ok: false, error: expect.stringContaining("changed while you were confirming") })
    expect(h.sent("update_account_limits")).toEqual([])
  })

  it("refuses a limits change that touches anything but limits, before asking", async () => {
    const h = harness(true)
    const config = withLimits({ max_order_usd: "250" })
    config.routes[0].connections[0].full_position_usd = "9999"
    expect(await h.api.act("updateAccountLimits", { configuration: config })).toMatchObject({ ok: false, error: expect.stringContaining("Only account limits") })
    expect(h.asked).toEqual([])
  })

  it("never plans two orders under one preview id", async () => {
    const h = harness(true)
    const preview = { preview_id: "pv-1", account_id: "zhap-account-2", lot_id: "lot-1", qty: "1" }
    expect(await h.api.read("previewLotSale", { preview })).toMatchObject({ ok: true })
    expect(await h.api.read("previewLotSale", { preview })).toMatchObject({ ok: false, error: "Each preview needs a new id." })
    expect(h.sent("preview_lot_sale")).toHaveLength(1)
  })

  it("will not start a setup whose keys are not in this app", async () => {
    const h = harness(true)
    const result = await h.api.act("startTrading", START)
    expect(result).toMatchObject({ ok: false, error: expect.stringContaining("keys are not in this app") })
    expect(h.asked).toEqual([])
  })

  it("only saves a setup while copying is paused", async () => {
    const h = harness(true)
    h.replies.get_trading_status = () => ({ type: "trading_status", trading: { state: "running" } })
    const result = await h.api.act("saveSetup", { configuration: saved.configuration, revision: saved.revision })
    expect(result).toMatchObject({ ok: false, error: expect.stringContaining("Pause copying") })
  })

  it("answers an unknown or inherited name with an error and sends nothing", async () => {
    const h = harness(true)
    for (const name of ["nope", "toString", "__proto__", 7, undefined]) {
      expect(await h.api.read(name, undefined)).toMatchObject({ ok: false })
      expect(await h.api.act(name, undefined)).toMatchObject({ ok: false })
    }
    expect(await h.api.read("getStatus", [1])).toMatchObject({ ok: false })
    expect(h.requests).toEqual([])
  })
})

describe("secrets", () => {
  function withKeys() {
    const h = harness(true)
    h.secrets.setRevision(saved.secretRevision)
    h.secrets.merge({
      discord_token: DISCORD,
      provider_api_key: PROVIDER,
      brokers: [{ account_id: "zhap-account-2", key: BROKER_KEY, secret: BROKER_SECRET }],
    })
    return h
  }

  it("go to the engine inside the requests that need them", async () => {
    const h = withKeys()
    await h.api.act("validateTrading", { configuration: saved.configuration })
    expect(h.sent("validate_trading")[0]!.params.secrets).toMatchObject({ discord_token: DISCORD, provider_api_key: PROVIDER })
    await h.api.act("checkConnection", { connection: { kind: "broker", account: saved.configuration.accounts[0] } })
    expect(h.sent("check_connection")[0]!.params.connection).toMatchObject({ credentials: { key: BROKER_KEY, secret: BROKER_SECRET } })
    await h.api.act("checkConnection", { connection: { kind: "model", provider: saved.configuration.provider } })
    expect(h.sent("check_connection")[1]!.params.connection).toMatchObject({ api_key: PROVIDER })
    await h.api.act("learnGuruPlaybook", { channel_id: "1", provider: saved.configuration.provider })
    expect(h.sent("learn_guru_playbook")[0]!.params).toMatchObject({ discord_token: DISCORD, provider_api_key: PROVIDER })
  })

  it("are not replaced by keys a page sends along", async () => {
    const h = withKeys()
    await h.api.act("validateTrading", { configuration: saved.configuration, secrets: { discord_token: "attacker" } })
    expect(h.sent("validate_trading")[0]!.params.secrets).toMatchObject({ discord_token: DISCORD })
    await h.api.act("learnGuruPlaybook", { channel_id: "1", provider: saved.configuration.provider, discord_token: "attacker", provider_api_key: "attacker" })
    expect(h.sent("learn_guru_playbook")[0]!.params).toMatchObject({ discord_token: DISCORD, provider_api_key: PROVIDER })
  })

  it("never come back in a reply, even when the engine echoes the whole request", async () => {
    const h = withKeys()
    h.replies.validate_trading = (p) => ({ type: "trading_validation", report: { echoed: p }, activation_token: null })
    h.replies.check_connection = (p) => ({ type: "connection_check", check: p.connection })
    const validation = JSON.stringify(await h.api.act("validateTrading", { configuration: saved.configuration }))
    const check = JSON.stringify(await h.api.act("checkConnection", { connection: { kind: "source", source: saved.configuration.source } }))
    for (const text of [validation, check]) {
      for (const secret of [DISCORD, PROVIDER, BROKER_KEY, BROKER_SECRET]) expect(text).not.toContain(secret)
      expect(JSON.parse(text)).toMatchObject({ ok: false })
    }
  })

  it("never come back in an error", async () => {
    const h = withKeys()
    h.replies.validate_trading = () => {
      throw new Error(`engine said no to ${DISCORD}`)
    }
    const result = JSON.stringify(await h.api.act("validateTrading", { configuration: saved.configuration }))
    expect(result).not.toContain(DISCORD)
  })

  it("are reported as saved or not, never as values", async () => {
    const h = withKeys()
    const status = await h.api.read("getSecretStatus", undefined)
    expect(status).toEqual({
      ok: true,
      value: { discord_token: true, provider_api_key: true, notification_token: false, brokers: { "zhap-account-2": true } },
    })
    const setup = await h.api.read("getSetup", undefined)
    expect(setup).toMatchObject({ ok: true, value: { keys_present: true } })
    expect(JSON.stringify(setup)).not.toContain("secretRevision")
  })

  it("are encrypted on disk", () => {
    const h = withKeys()
    const file = readFileSync(join(h.dir, "secrets.bin"))
    for (const secret of [DISCORD, PROVIDER, BROKER_KEY, BROKER_SECRET]) expect(file.includes(secret)).toBe(false)
    expect(new SecretStore(join(h.dir, "secrets.bin"), cipher).secrets.discord_token).toBe(DISCORD)
  })

  it("are removed from the engine's stopped-reason before the footer shows it", () => {
    const reason = `Traceback ... token=${DISCORD} key=${PROVIDER}`
    const shown = redactState({ state: "stopped", reason }, [DISCORD, PROVIDER])
    expect(shown).toEqual({ state: "stopped", reason: "Traceback ... token=••• key=•••" })
    expect(redactState({ state: "running" }, [DISCORD])).toEqual({ state: "running" })
  })

  it("name what is missing instead of sending a request that cannot work", async () => {
    const h = harness(true)
    expect(await h.api.act("validateTrading", { configuration: saved.configuration })).toMatchObject({ ok: false, error: "The Discord token is not saved yet." })
    expect(await h.api.act("checkConnection", { connection: { kind: "broker", account: saved.configuration.accounts[0] } })).toMatchObject({
      ok: false,
      error: "No keys are saved for zhap-account-2.",
    })
    expect(h.requests).toEqual([])
  })

  it("send a model key only to the provider it was typed for", async () => {
    const h = harness(true)
    h.secrets.setRevision(saved.secretRevision)
    h.secrets.merge({ discord_token: DISCORD, provider_api_key: PROVIDER, provider_name: "deepseek" })
    await h.api.act("checkConnection", { connection: { kind: "model", provider: { name: "anthropic", model: "m" } } })
    expect(h.sent("check_connection")[0]!.params.connection).toMatchObject({ api_key: "" })
    await h.api.act("learnGuruPlaybook", { channel_id: "1", provider: { name: "openai", model: "m" } })
    expect(h.sent("learn_guru_playbook")[0]!.params).toMatchObject({ provider_api_key: "" })
    await h.api.act("checkConnection", { connection: { kind: "model", provider: { name: "deepseek", model: "m" } } })
    expect(h.sent("check_connection")[1]!.params.connection).toMatchObject({ api_key: PROVIDER })
    const other = { ...saved.configuration, provider: { name: "anthropic", model: "m" } }
    await h.api.act("validateTrading", { configuration: other })
    expect(h.sent("validate_trading")[0]!.params.secrets).toMatchObject({ provider_api_key: "" })
  })

  it("send only the accounts the setup has, and no alert token without alerts", async () => {
    const h = harness(true)
    h.secrets.merge({
      discord_token: DISCORD,
      notification_token: "SENTINEL-alert-token-0005",
      brokers: [
        { account_id: "zhap-account-2", key: BROKER_KEY, secret: BROKER_SECRET },
        { account_id: "removed-account", key: "SENTINEL-removed-key-0006", secret: "SENTINEL-removed-secret-0007" },
      ],
    })
    const { notification: _alerts, ...withoutAlerts } = saved.configuration
    await h.api.act("validateTrading", { configuration: withoutAlerts })
    const sent = h.sent("validate_trading")[0]!.params.secrets as { brokers: { account_id: string }[]; notification_token?: string }
    expect(sent.brokers.map((b) => b.account_id)).toEqual(["zhap-account-2"])
    expect(sent).not.toHaveProperty("notification_token")
    await h.api.act("validateTrading", { configuration: saved.configuration })
    expect(h.sent("validate_trading")[1]!.params.secrets).toMatchObject({ notification_token: "SENTINEL-alert-token-0005" })
  })
})

describe("start journal", () => {
  const COMMITTED = {
    phase: "ready", runtime_state: "running", activation_id: ACTIVATION, candidate_revision: saved.revision,
    committed_revision: saved.revision, committed_activation_id: ACTIVATION, error_code: null,
  }
  const FAILED = { phase: "failed", runtime_state: "paused", activation_id: ACTIVATION, candidate_revision: saved.revision, committed_revision: null, error_code: "accounts_unavailable" }
  const onDisk = (h: Harness) => JSON.parse(readFileSync(join(h.dir, SETUP_FILE), "utf8"))
  const activation = (h: Harness, status: Record<string, unknown>) => {
    h.replies.get_trading_activation = () => ({ type: "trading_activation", activation: status })
  }

  /** A harness whose saved setup was just replaced by a changed one, with this app's keys for it. */
  async function changed(answer = true) {
    const h = harness(answer)
    h.secrets.setRevision(saved.secretRevision)
    h.secrets.merge({ discord_token: DISCORD })
    const candidate = withLimits({ max_order_usd: "250" })
    expect(await h.api.act("saveSetup", { configuration: candidate, revision: "b".repeat(64) })).toMatchObject({ ok: true })
    return { h, candidate }
  }

  it("saves the candidate for good once the engine commits it", async () => {
    const { h, candidate } = await changed()
    h.replies.get_trading_status = () => ({ type: "trading_status", trading: { state: "running" } })
    activation(h, { ...COMMITTED, candidate_revision: "b".repeat(64), committed_revision: "b".repeat(64) })
    expect(await h.api.act("startTrading", START)).toMatchObject({ ok: true, value: { state: "running" } })
    expect(onDisk(h)).toMatchObject({ configuration: candidate, revision: "b".repeat(64) })
    expect(onDisk(h)).not.toHaveProperty("pendingActivation")
    expect(await h.api.read("getSetup", undefined)).toMatchObject({ ok: true, value: { pending_activation: null, keys_present: true } })
  })

  it("journals the start before it is sent, with the setup to put back", async () => {
    const { h } = await changed()
    h.replies.start_trading = () => {
      expect(onDisk(h).pendingActivation).toMatchObject({ activationID: ACTIVATION, candidateRevision: "b".repeat(64), previous: { revision: saved.revision } })
      return { type: "ok", trading: {} }
    }
    activation(h, { ...COMMITTED, candidate_revision: "b".repeat(64), committed_revision: "b".repeat(64) })
    await h.api.act("startTrading", START)
    expect(h.sent("start_trading")).toHaveLength(1)
  })

  it("leaves a start the engine is still committing pending, showing the setup before it", async () => {
    const { h } = await changed()
    activation(h, { ...COMMITTED, phase: "starting", runtime_state: "starting", committed_revision: null, committed_activation_id: null })
    expect(await h.api.act("startTrading", START)).toMatchObject({ ok: true })
    expect(await h.api.read("getSetup", undefined)).toMatchObject({
      ok: true,
      value: { revision: saved.revision, pending_activation: { activation_id: ACTIVATION, candidate_revision: "b".repeat(64) } },
    })
    // Another start is refused until this one settles.
    expect(await h.api.act("startTrading", { ...START, activation_id: "9d3f2c1a-0000-4000-8000-000000000002" })).toMatchObject({
      ok: false,
      error: expect.stringContaining("still waiting"),
    })
  })

  it("puts the setup before it back when the engine stops without committing, and says why", async () => {
    const { h } = await changed()
    activation(h, FAILED)
    h.replies.get_trading_status = () => ({
      type: "trading_status",
      trading: { state: "paused", accounts: [{ id: "zhap-account-2", state: "failed", error_code: "broker_keys_rejected" }] },
    })
    const result = await h.api.act("startTrading", START)
    expect(result).toMatchObject({
      ok: false,
      error:
        "The new setup didn't start, so your previous setup is still in place. zhap-account-2 didn't open: Alpaca didn't accept its API keys. Paste them again from your Alpaca dashboard.",
    })
    expect(onDisk(h)).toMatchObject({ configuration: saved.configuration, revision: saved.revision, secretRevision: saved.secretRevision })
    expect(onDisk(h)).not.toHaveProperty("pendingActivation")
    expect(h.secrets.revision).toBe(saved.secretRevision)
  })

  it("keeps nothing it saved when the owner says no in the dialog", async () => {
    const { h } = await changed(false)
    expect(await h.api.act("startTrading", START)).toMatchObject({ ok: false, cancelled: true })
    expect(h.sent("start_trading")).toEqual([])
    expect(onDisk(h)).toMatchObject({ configuration: saved.configuration, secretRevision: saved.secretRevision })
    expect(h.secrets.revision).toBe(saved.secretRevision)
  })

  it("rolls back at once when the engine refuses the start", async () => {
    const { h } = await changed()
    h.replies.start_trading = () => {
      throw new EngineError("engine", "invalid_request")
    }
    expect(await h.api.act("startTrading", START)).toMatchObject({
      ok: false,
      error: "Copying didn't start. The engine did not accept the request.",
    })
    expect(onDisk(h)).toMatchObject({ configuration: saved.configuration })
    expect(h.sent("get_trading_activation")).toEqual([])
  })

  it("settles a start whose reply was lost from the engine's record of it", async () => {
    const { h } = await changed()
    h.replies.start_trading = () => {
      throw new EngineError("timed_out", "The engine did not answer in time.")
    }
    activation(h, { ...COMMITTED, candidate_revision: "b".repeat(64), committed_revision: "b".repeat(64) })
    expect(await h.api.act("startTrading", START)).toMatchObject({ ok: true })
    expect(onDisk(h)).not.toHaveProperty("pendingActivation")
  })

  it("settles a start a crash left pending the next time the engine is asked for its status", async () => {
    const h = harness(true)
    h.secrets.setRevision(saved.secretRevision)
    h.setup.stage(ACTIVATION)
    expect(onDisk(h).pendingActivation).toBeDefined()
    activation(h, COMMITTED)
    await h.api.read("getStatus", undefined)
    expect(onDisk(h)).not.toHaveProperty("pendingActivation")
  })

  it("does not take an activation record that is not this setup's as a commit", async () => {
    const { h } = await changed()
    // The engine runs another setup (the previous one), so the candidate is not committed.
    activation(h, { ...COMMITTED, phase: "starting", runtime_state: "running", candidate_revision: "b".repeat(64), committed_revision: saved.revision })
    await h.api.act("startTrading", START)
    expect(onDisk(h).pendingActivation).toBeDefined()
  })
})
