import { copyFileSync, mkdtempSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { type Engine, createApi } from "../electron/main/api"
import { SecretStore } from "../electron/main/secrets"
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
  "approve_proposal", "delete_account_record", "complete_restore_candidate",
]

function harness(answer = true) {
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
  const api = createApi({
    engine,
    setup: new SetupFile(dir),
    secrets,
    confirm: async (text) => {
      asked.push(text)
      return answer
    },
  })
  return { api, secrets, requests, asked, replies, dir, sent: (op: string) => requests.filter((r) => r.op === op) }
}

type Harness = ReturnType<typeof harness>

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
    "Start copying 赵哥, Standard stock alerts into zhap-account-2 (paper), zhap-account-3 (paper)?\n\nThis places paper orders.",
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
    await h.api.act("startTrading", { activation_id: "a", validation_token: "t", configuration: { version: 10, routes: [] } })
    expect(h.sent("start_trading")[0]!.params.configuration).toEqual(saved.configuration)
  })

  it("will not start a setup whose keys are not in this app", async () => {
    const h = harness(true)
    const result = await h.api.act("startTrading", { activation_id: "a", validation_token: "t" })
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

  it("name what is missing instead of sending a request that cannot work", async () => {
    const h = harness(true)
    expect(await h.api.act("validateTrading", { configuration: saved.configuration })).toMatchObject({ ok: false, error: "The Discord token is not saved yet." })
    expect(await h.api.act("checkConnection", { connection: { kind: "broker", account: saved.configuration.accounts[0] } })).toMatchObject({
      ok: false,
      error: "No keys are saved for zhap-account-2.",
    })
    expect(h.requests).toEqual([])
  })
})
