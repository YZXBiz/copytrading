import { ACTS, type ActName, READS, type ReadName, type Result, type TradingConfiguration } from "../../shared/contract"
import {
  PAUSE_TEXT,
  Refusal,
  controlText,
  deleteRecordText,
  limitsText,
  lotSaleText,
  manualOrdersText,
  proposalText,
  restoreText,
  startText,
} from "./confirmations"
import { randomUUID } from "node:crypto"
import { isDeepStrictEqual } from "node:util"
import { PROVIDER_TITLES } from "../../shared/providers"
import { startFailure } from "../../shared/start-failure"
import { EngineError } from "./engine/bridge"
import { readJournal } from "./journal"
import { type SecretStore, type Secrets, redact } from "./secrets"
import { SetupFile, SetupFileError } from "./setup-file"

export interface Engine {
  request(operation: string, params?: Record<string, unknown>): Promise<unknown>
}

export interface Deps {
  engine: Engine
  setup: SetupFile
  secrets: SecretStore
  /** Shows the owner a native yes/no; resolves false for no. Production: dialog.showMessageBox in main. */
  confirm: (text: string) => Promise<boolean>
  /** The folder the engine writes its journal to; absent where there is none (fixtures). */
  diagnosticsDir?: string
  /** A native file dialog: where to save a backup, or which backup to open. null for Cancel. */
  pick?: (kind: "backup-destination" | "restore-archive") => Promise<string | null>
  /** How long a start waits for the engine to confirm it before leaving it pending. Default: 30 looks, a second apart. */
  activation?: { looks: number; waitMs: number }
}

type Params = Record<string, unknown>
interface Ctx extends Deps {
  /** Previews the engine planned this session, by preview id: what a later confirmation asks about. */
  seen: Map<string, unknown>
  /** A start is being looked at; a second look waits for the next time. */
  settling: boolean
  /** How each start this session ended, by activation id: null committed, otherwise the words for why it did not take. */
  outcomes: Map<string, string | null>
}
type Handler = (params: Params, ctx: Ctx) => Promise<unknown>
/** What a confirmation says, and the params to send in place of the page's when main knows better. */
type Describe = (params: Params, ctx: Ctx) => Promise<{ text: string; send?: Params }> | { text: string; send?: Params }

const ENGINE_WORDS: Record<string, string> = {
  unavailable: "The engine is not ready to answer yet.",
  not_found: "The engine has no record of this.",
  invalid_request: "The engine did not accept the request.",
  identity_conflict: "The engine belongs to a different installation.",
}

const WITHHELD = "A reply held a saved key, so it was not shown."

type Payload = Record<string, unknown>
const body = (payload: unknown) => payload as Payload
/** The reply's `key` field. */
const value = (key: string) => (payload: unknown) => body(payload)[key]
/** The reply's `key` field, wrapped as an object. */
const field = (key: string) => (payload: unknown) => ({ [key]: body(payload)[key] })
/** The whole reply, without its `type`. */
const whole = (payload: unknown) => {
  const { type: _type, ...rest } = body(payload)
  return rest
}
const nothing = () => null

const ask =
  (operation: string, reply: (payload: unknown) => unknown, build: (params: Params, ctx: Ctx) => Params | Promise<Params> = (p) => p): Handler =>
  async (params, ctx) =>
    reply(await ctx.engine.request(operation, await build(params, ctx)))

const needToken = (secrets: Secrets) => {
  if (!secrets.discord_token) throw new Refusal("The Discord token is not saved yet.")
  return secrets.discord_token
}

function savedSetup({ setup, secrets }: Ctx) {
  const saved = setup.load()
  if (!saved) throw new Refusal("There is no saved setup yet.")
  if (secrets.revision?.toLowerCase() !== saved.secretRevision.toLowerCase()) {
    throw new Refusal("This setup's saved keys are not in this app yet.")
  }
  return saved
}

/** The model key for the provider a request names: a key typed for another provider is never sent to it. */
const providerKey = (ctx: Ctx, provider: unknown): string =>
  ctx.secrets.providerKey(String((provider as { name?: unknown } | undefined)?.name), ctx.setup.current()?.configuration.provider.name)

/** The pieces a handler for one operation sends that only main may fill in. */
const withKeys = (ctx: Ctx, params: Params, keys: (secrets: Secrets, provider_api_key: string) => Params) =>
  keys(ctx.secrets.secrets, providerKey(ctx, params.provider))

/** What `validate_trading` and `start_trading` take: only the keys this setup uses, so a removed account's keys never reach the engine. */
function engineSecrets(configuration: TradingConfiguration, ctx: Ctx): Secrets {
  const { secrets } = ctx.secrets
  const accounts = new Set(configuration.accounts.map((a) => a.id))
  return {
    discord_token: secrets.discord_token,
    provider_api_key: ctx.secrets.providerKey(configuration.provider.name, ctx.setup.current()?.configuration.provider.name),
    brokers: secrets.brokers.filter((b) => accounts.has(b.account_id)),
    ...(configuration.notification && secrets.notification_token ? { notification_token: secrets.notification_token } : {}),
  }
}

function connection(check: Params, secrets: Secrets, ctx: Ctx): Params {
  switch (check.kind) {
    case "source":
      return { ...check, token: needToken(secrets) }
    case "model":
      return { ...check, api_key: providerKey(ctx, check.provider) }
    case "broker": {
      const id = (check.account as { id: string }).id
      const keys = secrets.brokers.find((b) => b.account_id === id)
      if (!keys) throw new Refusal(`No keys are saved for ${id}.`)
      return { ...check, credentials: { account_id: id, key: keys.key, secret: keys.secret } }
    }
    case "notification":
      if (!secrets.notification_token) throw new Refusal("The alert token is not saved yet.")
      return { ...check, token: secrets.notification_token }
    default:
      throw new Refusal("That is not a service that can be checked.")
  }
}

async function pausedOrRefuse(ctx: Ctx) {
  const state = body(body(await ctx.engine.request("get_trading_status")).trading).state
  if (state !== "paused") throw new Refusal("Pause copying before changing the setup.")
}

const READ_HANDLERS: Record<ReadName, Handler> = {
  getStatus: async (params, ctx) => {
    await settleOnce(ctx).catch(() => {}) // a start a crash left pending; its failure shows in the status
    return ask("get_trading_status", value("trading"))(params, ctx)
  },
  getEngineStatus: ask("get_status", value("status")),
  getTradingActivation: ask("get_trading_activation", value("activation")),
  getWorkflow: ask("get_workflow", value("workflow")),
  getAccounts: ask("get_accounts", value("accounts"), () => ({ limit: 100 })),
  getEquityHistory: ask("get_equity_history", value("history"), ({ account_id, range, day }) => ({
    account_id,
    window: range === "day" && day ? { range, day } : { range },
  })),
  getSourceActivity: ask("get_source_activity", value("activity")),
  getGuruActivity: ask("get_guru_activity", value("activity")),
  getGuruDayStats: ask("get_guru_day_stats", value("stats")),
  getAccountFeed: ask("get_account_feed", value("feed")),
  getQuote: ask("get_quote", value("quote")),
  getManualCommand: ask("get_manual_command", value("command")),
  listManualCommands: ask("list_manual_commands", value("commands")),
  previewManualOrder: (params, ctx) => preview(ctx, "preview_manual_order", params),
  previewLotSale: (params, ctx) => preview(ctx, "preview_lot_sale", params),
  listProposals: ask("list_proposals", value("proposals")),
  getAgentAudit: ask("agent_audit", value("entries")),
  getRestoreCandidate: ask("restore_candidate_status", value("candidate")),
  getAssistantTurn: ask("assistant_turn", whole),
  getSetup: async (_params, ctx) => {
    await settleOnce(ctx).catch(() => {})
    const saved = ctx.setup.load()
    if (!saved) return null
    const { secretRevision, ...view } = saved
    return { ...view, keys_present: ctx.secrets.revision?.toLowerCase() === secretRevision.toLowerCase() }
  },
  getLimits: async ({ account_id }, { setup }) => {
    const config = setup.load()?.configuration
    const account = config?.accounts.find((a) => a.id === account_id)
    const route = config?.routes.find((r) => r.connections.some((c) => c.account_id === account_id))
    const connectionOf = route?.connections.find((c) => c.account_id === account_id)
    if (!config || !account || !route || !connectionOf) return null
    const guru = config.profiles.find((p) => p.guru_id === route.guru_id && p.profile_revision === route.profile_revision)
    return {
      guru: guru?.display_name ?? route.guru_id,
      full_position_usd: Number(connectionOf.full_position_usd),
      daily_loss_cap_usd: Number(account.policy.daily_loss_cap_usd),
      max_total_usd: Number(account.policy.max_total_usd),
      max_order_usd: Number(account.policy.max_order_usd),
      max_symbol_usd: Number(account.policy.max_symbol_usd),
      max_entries_per_day: account.policy.max_entries_per_day,
    }
  },
  getSecretStatus: async (_params, { secrets }) => secrets.status(),
  readDiagnostics: async ({ limit }, { diagnosticsDir }) => {
    if (!diagnosticsDir) throw new Refusal("There is no log to read here.")
    return readJournal(diagnosticsDir, typeof limit === "number" && limit > 0 ? Math.min(limit, 5000) : undefined)
  },
}

/** Proposals only the app can carry out: the engine leaves them running until the app reports back (control/proposals.py APP_PERFORMED). */
const APP_PERFORMED = new Set(["set_recovery", "set_account_limits", "start_processing", "apply_setup"])

/** The accounts a restore candidate holds, each with its environment from the saved setup and its keys from the store; refuses if any is missing. */
async function preflightAccounts(ctx: Ctx, candidateId: string) {
  const candidate = body(await ctx.engine.request("restore_candidate_status")).candidate as { candidate_id: string; account_ids: string[] } | null
  if (!candidate || candidate.candidate_id !== candidateId) throw new Refusal("The engine has no restore waiting under that id.")
  const configured = ctx.setup.load()?.configuration.accounts ?? []
  return candidate.account_ids.map((account_id) => {
    const environment = configured.find((a) => a.id === account_id)?.environment
    const keys = ctx.secrets.secrets.brokers.find((b) => b.account_id === account_id)
    if (!environment || !keys) throw new Refusal(`The backup needs ${account_id}, and this setup has no keys saved for it. Add it in Connections first.`)
    return { account_id, environment, key: keys.key, secret: keys.secret }
  })
}

/** Asks the engine to plan an order and keeps the plan. An id used once is never reused, so a plan cannot change under a dialog. */
async function preview(ctx: Ctx, operation: string, params: Params): Promise<unknown> {
  const id = (params.preview as { preview_id?: string } | undefined)?.preview_id
  if (typeof id !== "string" || ctx.seen.has(id)) throw new Refusal("Each preview needs a new id.")
  const planned = value("preview")(await ctx.engine.request(operation, params))
  ctx.seen.set(id, planned)
  return planned
}

/** Runs `handler` only after the owner says yes to what `describe` says it will do. */
const confirmed =
  (describe: Describe, handler: Handler, onCancel?: (ctx: Ctx) => void): Handler =>
  async (params, ctx) => {
    const { text, send } = await describe(params, ctx)
    if (!(await ctx.confirm(text))) {
      onCancel?.(ctx)
      throw new Cancelled()
    }
    return handler(send ?? params, ctx)
  }

class Cancelled extends Error {}

const sleep = (ms: number) => new Promise((done) => setTimeout(done, ms))

interface Activation {
  phase: string
  runtime_state: string
  activation_id: string | null
  candidate_revision: string | null
  committed_revision: string | null
  committed_activation_id?: string | null
  error_code: string | null
}

/**
 * One look at the start the setup file says is waiting, with the rules AppModel.reconcilePendingTradingActivation uses:
 * the engine committing exactly this setup finalizes it; the engine stopped without committing rolls it back and says why
 * (as a Refusal); anything else leaves it pending. A look the engine cannot answer leaves it pending too.
 */
async function settleOnce(ctx: Ctx): Promise<"committed" | "pending"> {
  const pending = ctx.setup.pending()
  if (!pending || ctx.settling) return pending ? "pending" : "committed"
  ctx.settling = true
  try {
    let status: Activation
    try {
      status = body(await ctx.engine.request("get_trading_activation", { activation_id: pending.activation_id })).activation as Activation
    } catch {
      return "pending"
    }
    if (!status) return "pending"
    const id = pending.activation_id
    const candidate = pending.candidate_revision
    const runsCandidate = status.phase !== "starting" && status.committed_revision === candidate && ["running", "degraded"].includes(status.runtime_state)
    const committed =
      runsCandidate ||
      (status.activation_id === id && status.candidate_revision === candidate && status.committed_revision === candidate && status.committed_activation_id === id)
    if (committed && (runsCandidate || status.phase === "ready" || status.phase === "stopped")) {
      ctx.setup.finalize(id)
      ctx.secrets.settle()
      ctx.outcomes.set(id, null)
      return "committed"
    }
    const ended = ["failed", "stopped", "interrupted", "not_found"].includes(status.phase) && ["paused", "failed"].includes(status.runtime_state)
    if (!ended || committed) return "pending"
    const before = ctx.setup.load()?.configuration
    const started = ctx.setup.current()?.configuration
    const accounts = (body(body(await ctx.engine.request("get_trading_status")).trading).accounts ?? []) as { id: string; state: string; error_code: string | null }[]
    const why = startFailure(status.error_code, accounts, PROVIDER_TITLES[started?.provider.name ?? "anthropic"])
    ctx.setup.rollback(id)
    ctx.secrets.rollback()
    const message = !before || isDeepStrictEqual(before, started) ? `Copying didn't start. ${why}` : `The new setup didn't start, so your previous setup is still in place. ${why}`
    // A look from a status read may settle a start that `startTrading` is still waiting on: it reads the outcome from here.
    ctx.outcomes.set(id, message)
    throw new Refusal(message)
  } finally {
    ctx.settling = false
  }
}

/**
 * After a start the owner already approved copying into every account in the setup (the dialog named each), so each one
 * the engine holds with buys off is resumed, as AppModel.turnOnEveryAccount does. The engine opens accounts one at a time,
 * so this looks again for a while before giving up on one.
 */
async function turnOnAccounts(ctx: Ctx, wanted: string[]): Promise<void> {
  const { looks, waitMs } = ctx.activation ?? { looks: 30, waitMs: 1000 }
  const done = new Set<string>()
  for (let look = 0; look < looks && done.size < wanted.length; look++) {
    if (look) await sleep(waitMs)
    let items: { account_id: string; active_configuration?: boolean; entry_permission: string }[]
    try {
      items = (body(body(await ctx.engine.request("get_accounts", { limit: 100 })).accounts).items ?? []) as typeof items
    } catch {
      continue
    }
    for (const account of items) {
      if (!wanted.includes(account.account_id) || done.has(account.account_id) || !account.active_configuration) continue
      done.add(account.account_id)
      if (account.entry_permission === "enabled") continue
      await ctx.engine
        .request("control_account", { command: { command_id: randomUUID(), account_id: account.account_id, action: "resume" } })
        .catch(() => {}) // the account's page says it is still paused
    }
  }
}

/** A setup saved for a start that was never sent: the setup before it is saved again, and the keys typed for it are dropped. */
function discardUnstarted(ctx: Ctx): void {
  ctx.setup.discardUnstarted()
  ctx.secrets.discard()
}

/**
 * Journals a start, sends it, and waits for the engine to commit it. The keys go to disk with the start (the ones before
 * it are kept), so a start that does not take leaves the key store as it was. Returns null once committed, the words for
 * why it did not take as a Refusal, and undefined while the engine has not said (the page keeps looking).
 */
async function runStart(ctx: Ctx, request: Params): Promise<null | undefined> {
  const id = String(request.activation_id)
  ctx.setup.stage(id)
  try {
    ctx.secrets.stage()
  } catch {
    ctx.setup.rollback(id)
    ctx.secrets.discard()
    throw new Refusal("The keys could not be saved on this Mac, so nothing was started.")
  }
  try {
    await ctx.engine.request("start_trading", request)
  } catch (error) {
    if (error instanceof EngineError && error.code === "engine") {
      // The engine answered no: nothing started, so the setup and keys before it are saved again.
      ctx.setup.rollback(id)
      ctx.secrets.rollback()
      throw new Refusal(`Copying didn't start. ${words(error)}`)
    }
    // No answer: the engine's activation record, read below, says whether it took.
  }
  const { looks, waitMs } = ctx.activation ?? { looks: 30, waitMs: 1000 }
  for (let look = 0; look < looks && !ctx.outcomes.has(id); look++) {
    await settleOnce(ctx)
    if (ctx.outcomes.has(id)) break
    await sleep(waitMs)
  }
  const outcome = ctx.outcomes.get(id)
  if (outcome) throw new Refusal(outcome)
  return outcome === null ? null : undefined
}

const ACT_HANDLERS: Record<ActName, Handler> = {
  confirmManualOrders: confirmed(
    (p, ctx) => ({ text: manualOrdersText(p.commands as never, ctx.seen) }),
    ask("confirm_manual_orders", value("commands"), (p) => ({ commands: p.commands })),
  ),
  confirmLotSale: confirmed(
    (p, ctx) => ({ text: lotSaleText(p.sale as never, ctx.seen) }),
    ask("confirm_lot_sale", value("sale"), (p) => ({ sale: p.sale })),
  ),
  startTrading: confirmed(
    // The setup and keys are read once, here: the request carries exactly what the dialog described,
    // even if the page saves another setup or key while the dialog is open.
    async (p, ctx) => {
      await settleOnce(ctx).catch(() => {}) // an earlier start is settled first; if it is still pending, this one is refused below
      const { configuration, revision, secretRevision } = ctx.setup.current() ?? savedSetup(ctx)
      if (ctx.setup.pending()) throw new Refusal("The last start is still waiting for the engine to confirm it.")
      if (ctx.secrets.revision?.toLowerCase() !== secretRevision.toLowerCase()) throw new Refusal("This setup's saved keys are not in this app yet.")
      return {
        text: startText(configuration),
        send: { configuration, revision, secrets: engineSecrets(configuration, ctx), validation_token: p.validation_token, activation_id: p.activation_id },
      }
    },
    async ({ revision, ...request }, ctx) => {
      // The file is what the dialog described, or nothing starts: a page cannot swap the setup while the dialog is open.
      const now = ctx.setup.current()
      if (!now || now.revision !== revision || !isDeepStrictEqual(now.configuration, request.configuration)) throw new Refusal("The saved setup changed while you were confirming. Try again.")
      const outcome = await runStart(ctx, request)
      if (outcome === null) await turnOnAccounts(ctx, (request.configuration as TradingConfiguration).accounts.map((a) => a.id))
      return value("trading")(await ctx.engine.request("get_trading_status"))
    },
    // Declined in the dialog: the setup saved for this start is not kept, and neither are the keys typed for it.
    discardUnstarted,
  ),
  pauseTrading: confirmed(() => ({ text: PAUSE_TEXT }), ask("pause_trading", value("trading"))),
  controlAccount: confirmed(
    (p) => ({ text: controlText(p.command as never) }),
    ask("control_account", value("control"), (p) => ({ command: p.command })),
  ),
  approveProposal: confirmed(
    async (p, ctx) => {
      const proposals = body(await ctx.engine.request("list_proposals")).proposals as { proposal_id: string; digest: string }[]
      const proposal = proposals.find((x) => x.proposal_id === p.proposal_id)
      if (!proposal) throw new Refusal("The engine has no such request waiting.")
      if (APP_PERFORMED.has((proposal as unknown as { subject: { kind: string } }).subject.kind)) {
        throw new Refusal("This request changes the saved setup, which this version cannot apply yet. Reject it, or approve it in the SwiftUI app.")
      }
      // The digest main holds is the one the dialog described; the page's is never sent.
      return { text: proposalText(proposal as never), send: { proposal_id: proposal.proposal_id, digest: proposal.digest } }
    },
    ask("approve_proposal", value("proposal")),
  ),
  deleteAccountRecord: confirmed(
    (p) => ({ text: deleteRecordText(String(p.account_id)) }),
    ask("delete_account_record", nothing, (p) => ({ account_id: p.account_id })),
  ),
  completeRestoreCandidate: confirmed(
    async (p, ctx) => ({
      text: restoreText(body(await ctx.engine.request("restore_candidate_status")).candidate as never, String(p.candidate_id)),
    }),
    ask("complete_restore_candidate", nothing, (p) => ({ candidate_id: p.candidate_id, completion_token: p.completion_token })),
  ),

  validateTrading: ask("validate_trading", whole, (p, ctx) => {
    needToken(ctx.secrets.secrets)
    return { configuration: p.configuration, secrets: engineSecrets(p.configuration as TradingConfiguration, ctx) }
  }),
  checkConnection: ask("check_connection", value("check"), (p, ctx) => ({
    connection: connection(p.connection as Params, ctx.secrets.secrets, ctx),
  })),
  // Copying takes new limits at once, so this asks too, wording the dialog from the difference to the saved setup.
  updateAccountLimits: confirmed(
    (p, { setup }) => {
      const saved = setup.load()
      if (!saved) throw new Refusal("There is no saved setup yet.")
      setup.assertLimitsOnly(p.configuration as TradingConfiguration)
      return { text: limitsText(saved.configuration, p.configuration as TradingConfiguration), send: { configuration: p.configuration, expect: saved.revision } }
    },
    async (p, ctx) => {
      const configuration = p.configuration as TradingConfiguration
      // Everything the file will check is checked before the engine hears of it, so the two cannot disagree.
      if (ctx.setup.load()?.revision !== p.expect) throw new Refusal("The saved setup changed while you were confirming. Try again.")
      ctx.setup.assertLimitsOnly(configuration)
      const revision = value("revision")(await ctx.engine.request("update_account_limits", { configuration })) as string
      ctx.setup.saveLimits(configuration, revision)
      return { revision }
    },
  ),
  saveSetup: async (p, ctx) => {
    await pausedOrRefuse(ctx)
    ctx.secrets.setRevision(ctx.setup.save(p.configuration as TradingConfiguration, String(p.revision)))
    return null
  },
  setSecrets: async (p, ctx) => {
    ctx.secrets.merge(p)
    return ctx.secrets.status()
  },
  discardSecrets: async (_p, ctx) => {
    ctx.secrets.discard()
    return ctx.secrets.status()
  },
  forgetBroker: async (p, ctx) => {
    ctx.secrets.forgetBroker(String(p.account_id))
    return ctx.secrets.status()
  },
  createBackup: ask("create_backup", value("manifest")),
  previewRestore: ask("preview_restore", value("preview")),
  prepareRestoreCandidate: ask("prepare_restore_candidate", field("candidate_id")),
  abortRestoreCandidate: ask("abort_restore_candidate", nothing),
  restorePreflight: ask("restore_preflight", whole, async (p, ctx) => ({
    candidate_id: p.candidate_id,
    accounts: await preflightAccounts(ctx, String(p.candidate_id)),
  })),
  resolveOwnership: ask("resolve_ownership", value("resolution")),
  saveManualCorrection: ask("save_manual_correction", value("correction")),
  rejectProposal: ask("reject_proposal", value("proposal")),
  completeProposal: ask("complete_proposal", value("proposal")),
  discardProposals: ask("discard_proposals", field("count")),
  learnGuruPlaybook: ask("learn_guru_playbook", value("playbook"), (p, ctx) => ({
    ...p,
    ...withKeys(ctx, p, (s, provider_api_key) => ({ discord_token: needToken(s), provider_api_key })),
  })),
  evaluateHistoricalProfile: ask("evaluate_historical_profile", value("evaluation"), (p, ctx) => ({
    ...p,
    ...withKeys(ctx, p, (_s, provider_api_key) => ({ provider_api_key })),
  })),
  assistantAsk: ask("assistant_ask", field("turn_id"), (p, ctx) => ({ ...p, ...withKeys(ctx, p, (_s, provider_api_key) => ({ provider_api_key })) })),
  assistantCancel: ask("assistant_cancel", field("cancelled")),
  assistantReset: ask("assistant_reset", nothing),
  submitSelfTest: ask("submit_self_test", value("workflow")),
  chooseBackupDestination: (_p, ctx) => pick(ctx, "backup-destination"),
  chooseRestoreArchive: (_p, ctx) => pick(ctx, "restore-archive"),
}

async function pick(ctx: Ctx, kind: "backup-destination" | "restore-archive") {
  if (!ctx.pick) throw new Refusal("There is no file dialog here.")
  return ctx.pick(kind)
}

function words(error: unknown): string {
  const text = error instanceof Error ? error.message : String(error)
  return error instanceof EngineError && error.code === "engine" ? (ENGINE_WORDS[text] ?? text) : text
}

/** The one place a reply, or an error, leaves for the renderer. It never carries a stored key. */
function reply(result: Result<unknown>, ctx: Ctx): Result<unknown> {
  const text = JSON.stringify(result)
  return redact(text, ctx.secrets.values()) !== text ? { ok: false, error: WITHHELD } : result
}

export function createApi(deps: Deps) {
  const ctx: Ctx = { ...deps, seen: new Map(), settling: false, outcomes: new Map() }
  const run = async (handlers: Record<string, Handler>, names: readonly string[], name: unknown, params: unknown): Promise<Result<unknown>> => {
    if (typeof name !== "string" || !names.includes(name)) return { ok: false, error: "The request was not valid." }
    if (params !== undefined && (typeof params !== "object" || params === null || Array.isArray(params))) {
      return { ok: false, error: "The request was not valid." }
    }
    try {
      return reply({ ok: true, value: await handlers[name]!((params ?? {}) as Params, ctx) }, ctx)
    } catch (error) {
      if (error instanceof Cancelled) return { ok: false, error: "Cancelled.", cancelled: true }
      return reply({ ok: false, error: error instanceof SetupFileError || error instanceof Refusal ? error.message : words(error) }, ctx)
    }
  }
  return {
    read: (name: unknown, params: unknown) => run(READ_HANDLERS, READS, name, params),
    act: (name: unknown, params: unknown) => run(ACT_HANDLERS, ACTS, name, params),
  }
}

export type Api = ReturnType<typeof createApi>
