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
}

type Params = Record<string, unknown>
interface Ctx extends Deps {
  /** Previews the engine planned this session, by preview id: what a later confirmation asks about. */
  seen: Map<string, unknown>
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

/** The pieces a handler for one operation sends that only main may fill in. */
const withKeys = (ctx: Ctx, keys: (secrets: Secrets) => Params) => keys(ctx.secrets.secrets)

function connection(check: Params, secrets: Secrets): Params {
  switch (check.kind) {
    case "source":
      return { ...check, token: needToken(secrets) }
    case "model":
      return { ...check, api_key: secrets.provider_api_key }
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
  getStatus: ask("get_trading_status", value("trading")),
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
  getSetup: async (_params, { setup, secrets }) => {
    const saved = setup.load()
    if (!saved) return null
    const { secretRevision, ...view } = saved
    return { ...view, keys_present: secrets.revision?.toLowerCase() === secretRevision.toLowerCase() }
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
  (describe: Describe, handler: Handler): Handler =>
  async (params, ctx) => {
    const { text, send } = await describe(params, ctx)
    if (!(await ctx.confirm(text))) throw new Cancelled()
    return handler(send ?? params, ctx)
  }

class Cancelled extends Error {}

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
    (p, ctx) => {
      const { configuration } = savedSetup(ctx)
      return {
        text: startText(configuration),
        send: { configuration, secrets: structuredClone(ctx.secrets.secrets), validation_token: p.validation_token, activation_id: p.activation_id },
      }
    },
    ask("start_trading", value("trading")),
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
    return { configuration: p.configuration, secrets: ctx.secrets.secrets }
  }),
  checkConnection: ask("check_connection", value("check"), (p, ctx) => ({
    connection: connection(p.connection as Params, ctx.secrets.secrets),
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
    ...withKeys(ctx, (s) => ({ discord_token: needToken(s), provider_api_key: s.provider_api_key })),
  })),
  evaluateHistoricalProfile: ask("evaluate_historical_profile", value("evaluation"), (p, ctx) => ({
    ...p,
    ...withKeys(ctx, (s) => ({ provider_api_key: s.provider_api_key })),
  })),
  assistantAsk: ask("assistant_ask", field("turn_id"), (p, ctx) => ({ ...p, ...withKeys(ctx, (s) => ({ provider_api_key: s.provider_api_key })) })),
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
  const ctx: Ctx = { ...deps, seen: new Map() }
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
