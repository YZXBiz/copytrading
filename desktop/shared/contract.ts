// What crosses the preload bridge. Money and share counts arrive as decimal strings (pydantic JSON
// mode); src/lib/format.ts parses them. Field names are the engine's own (snake_case).
//
// Every engine operation the SwiftUI app sends (app/Sources/DesktopCore/EngineClient.swift, the
// models in engine/src/copytrading_engine/host/pipe/requests.py) is in READS or ACTS, except
// MAIN_ONLY, which the main process uses itself and never offers to the renderer.
//
// Secrets never appear in a renderer request or reply: main adds them to the engine request
// (electron/main/operations.ts), so a type here omits the field the engine takes (`secrets`,
// `provider_api_key`, `discord_token`, `token`, `api_key`, `credentials`).

export type Decimal = string

/** `cancelled` is set when the owner said no in a confirmation: nothing went to the engine, and the page need show no error. */
export type Result<T> = { ok: true; value: T } | { ok: false; error: string; cancelled?: true }

// ── Engine state, owned by the main process ────────────────────────────────

export type EngineState =
  | { state: "starting" }
  | { state: "running" }
  | { state: "stopped"; reason: string }

// ── Trading status and activation ──────────────────────────────────────────

export type TradingRunState = "paused" | "starting" | "running" | "degraded" | "pausing" | "failed"

export interface TradingStatus {
  state: TradingRunState
  configured_accounts: number
  active_accounts: number
  source_connected: boolean
  model_ready: boolean
  pending_source?: number
  oldest_pending_source_at?: string | null
  pending_signals?: number
  oldest_pending_signal_at?: string | null
  processed_signals?: number
  error_code: string | null
  accounts?: { id: string; state: string; error_code: string | null }[]
}

export type TradingActivationPhase = "not_found" | "starting" | "ready" | "failed" | "stopped" | "interrupted"

export interface TradingActivationStatus {
  requested_activation_id: string
  activation_id: string | null
  candidate_revision: string | null
  committed_revision: string | null
  committed_activation_id?: string | null
  phase: TradingActivationPhase
  runtime_state: TradingRunState
  error_code: string | null
}

export interface EngineStatus {
  instance_id: string
  state: "starting" | "running" | "stopping" | "failed"
  accepted: number
  pending: number
  completed: number
  telemetry_state: "healthy" | "degraded"
  telemetry_dropped: number
  telemetry_error_code: string | null
}

export interface WorkflowView {
  command_id: string
  stage: "captured" | "parsed" | "completed" | "failed"
  outcomes: { account_id: string; result: "simulated" }[]
  trace_id: string
}

// ── The setup the owner saved (trading-configuration.json) ─────────────────

export type TradingEnvironment = "paper" | "live"
export type RecoveryPreference = "manual" | "automatic"

export type ProviderName =
  | "anthropic" | "openai" | "google" | "deepseek" | "openrouter" | "groq" | "xai"
  | "mistral" | "together" | "fireworks" | "cerebras" | "moonshotai" | "ollama" | "openai_compatible"

export interface TradingProvider {
  name: ProviderName
  model: string
  base_url?: string
}

export interface AccountPolicy {
  max_order_usd: string
  max_symbol_usd: string
  max_total_usd: string
  daily_loss_cap_usd: string
  max_entries_per_day: number
  max_signal_age_seconds: number
  order_timeout_seconds: number
  poll_seconds: number
  extended_hours: boolean
  overnight: boolean
  copy_exits: boolean
  approve_orders: boolean
  max_above_signal_pct: string
  max_below_signal_pct: string
  recovery_preference: RecoveryPreference
}

export interface TradingRoute {
  source: string
  channel_id: string
  author_id?: string
  guru_id: string
  profile_revision: string
  connections: { account_id: string; full_position_usd: string }[]
  /** null turns the repeat check off; absent in a saved file means ten minutes. */
  repeat_window_minutes: number | null
}

export interface TradingConfiguration {
  version: 10
  source: { channel_ids: string[]; author_ids: string[] }
  provider: TradingProvider
  accounts: { id: string; environment: TradingEnvironment; policy: AccountPolicy }[]
  profiles: { guru_id: string; display_name: string; playbook: string; profile_revision: string }[]
  routes: TradingRoute[]
  notification?: { service: "telegram" | "discord"; chat_id?: string }
}

/** The saved setup as the renderer sees it: the setup, the engine's revision of it, and no keys. */
export interface SetupView {
  configuration: TradingConfiguration
  /** The engine's revision of `configuration` (64 lowercase hex), as validation reported it. */
  revision: string
  /** The setup's keys are in this app's secret store; false until wave 3 moves the Keychain items. */
  keys_present: boolean
  /** A start the engine has not confirmed; `configuration` is then the last confirmed setup. */
  pending_activation: { activation_id: string; candidate_revision: string } | null
}

/** Which keys are saved; never their values. */
export interface SecretStatus {
  discord_token: boolean
  provider_api_key: boolean
  notification_token: boolean
  brokers: Record<string, boolean>
}

/** Keys the owner typed; `act.setSecrets` merges them into the encrypted store. */
export interface SecretUpdate {
  discord_token?: string
  provider_api_key?: string
  notification_token?: string
  brokers?: { account_id: string; key: string; secret: string }[]
}

/** The owner's saved limits for one account, from the saved setup. */
export interface AccountLimits {
  guru: string
  full_position_usd: number
  daily_loss_cap_usd: number
  max_total_usd: number
  max_order_usd: number
  max_symbol_usd: number
  max_entries_per_day: number
}

// ── Connections and activation ─────────────────────────────────────────────

/** One service the owner connects; main adds its key. */
export type ConnectionCheck =
  | { kind: "source"; source: { channel_ids: string[]; author_ids: string[] } }
  | { kind: "model"; provider: TradingProvider }
  | { kind: "broker"; account: { id: string; environment: TradingEnvironment; policy: AccountPolicy } }
  | { kind: "notification"; notification: { service: "telegram" | "discord"; chat_id?: string } }

export interface CapabilityCheck {
  name: "source" | "model" | "broker" | "notification" | "configuration"
  state: "ready" | "failed" | "not_configured"
  subject: string | null
  environment: TradingEnvironment | null
  identity: string | null
  adapter: string
  reason_code: string | null
  suggestion: string | null
  symbols: string[]
}

export interface TradingValidation {
  report: { configuration_revision: string; activatable: boolean; checks: CapabilityCheck[]; cost_notice: string }
  activation_token: string | null
}

// ── Accounts, positions, activity ──────────────────────────────────────────

export interface AccountBalance {
  equity: Decimal
  previous_close_equity: Decimal
  day_change_usd: Decimal
  cash: Decimal
  buying_power: Decimal
  observed_at: string
}

export interface PositionLot {
  lot_id: string
  guru_id: string | null
  posted_at: string | null
  remaining_qty: Decimal
  source_id?: string | null
  excerpt?: string | null
  bought_at?: string | null
  original_qty?: Decimal
  average_price?: Decimal
  unrealized_pl?: Decimal | null
}

export interface Position {
  symbol: string
  owned_qty: Decimal
  external_qty?: Decimal
  broker_qty?: Decimal | null
  lots: PositionLot[]
  avg_entry_price: Decimal | null
  current_price: Decimal | null
  market_value: Decimal | null
  unrealized_pl: Decimal | null
  unrealized_plpc: Decimal | null
}

export interface OwnershipIncident {
  incident_id: string
  symbol: string
  expected_qty: Decimal
  actual_qty: Decimal
  observed_at: string
  cause: string
}

export interface AccountOverview {
  account_id: string
  environment: TradingEnvironment
  entry_permission: string
  total_exposure_usd: Decimal | null
  positions: Position[]
  pending_orders: number | null
  balance: AccountBalance | null
  active_configuration?: boolean
  broker_identity?: string
  recovery_preference?: RecoveryPreference
  readiness?: string
  account_risk_status?: string
  account_risk_reason?: string | null
  account_activity_status?: string
  account_activity_reason?: string | null
  app_cost_basis_usd?: Decimal | null
  unresolved_incidents?: string[]
  ownership_incidents?: OwnershipIncident[]
  last_activity_at?: string | null
}

export interface AccountOverviewPage {
  items: AccountOverview[]
  unavailable_accounts: { account_id: string; reason: string }[]
  next_before_account_id?: string | null
}

export type HistoryRange = "day" | "week" | "month" | "three_months" | "year"

export interface EquityHistory {
  base_value: Decimal | null
  points: { at: string; equity: Decimal }[]
}

export interface SourceInstruction {
  action: "buy" | "reduce" | "close"
  symbol: string
  price: Decimal | null
  entry_price?: Decimal | null
  fraction?: Decimal | null
  usd_amount?: Decimal | null
  exit_basis?: string | null
}

export interface OrderActivity {
  client_id: string
  symbol: string
  side: string
  status: string
  quantity: Decimal
  filled_quantity: Decimal
  limit_price: Decimal | null
  average_fill_price: Decimal | null
  broker_id: string | null
  created_at: string
  instruction_index: number
  requested_usd?: Decimal | null
  budget_usd?: Decimal | null
  limited_by?: string | null
  order_type?: string | null
  session?: string | null
  submitted_at?: string | null
  cancel_reason?: string | null
  ended_at?: string | null
}

export interface DestinationActivity {
  account_id: string
  status: string
  instruction_outcomes: string[]
  environment?: string
  orders?: OrderActivity[]
  timeline?: { step: string; at: string; client_id: string | null; reason: string | null; quantity: Decimal | null; price: Decimal | null }[]
}

export interface SourceActivity {
  sequence: number
  source_at: string
  /** Untrusted Discord text: render it as text, never as HTML. */
  text: string
  decision: "trade" | "review" | "ignore" | null
  guru_id: string | null
  instructions: SourceInstruction[]
  destinations: DestinationActivity[]
  source_id?: string
  author_id?: string | null
  parse_status?: string
  delivery_status?: string
  parser_reason?: string | null
  suggested?: SourceInstruction[]
  read_started_at?: string | null
  read_at?: string | null
  delivered_at?: string | null
}

export interface SourceActivityPage {
  items: SourceActivity[]
  next_before_seq?: number | null
  unavailable_accounts?: { account_id: string; reason: string }[]
}

export interface GuruDayStats {
  guru_id: string
  posts: number
  traded: number
  read_seconds: number | null
  waiting: SourceActivity[]
}

export interface GuruDayStatsPage {
  items: GuruDayStats[]
}

export interface AccountFeedItem {
  sequence: number
  at: string
  kind: string
  source: string
  side: string | null
  symbol: string | null
  shares: Decimal | null
  price: Decimal | null
  amount: Decimal | null
  guru_id: string | null
  message_id: string | null
  order_id: string | null
  lot_id: string | null
  changes: { setting: string; before: string; after: string }[]
  reason: string | null
}

export interface AccountFeedPage {
  account_id: string
  items: AccountFeedItem[]
  next_before_seq: number | null
}

export interface MarketQuote {
  feed: string
  bid: Decimal | null
  ask: Decimal | null
  timestamp: string | null
}

// ── Orders the owner places (previews, then a confirmed command) ───────────

export interface ManualInstruction {
  action: "buy" | "reduce" | "close"
  symbol: string
  price: Decimal | null
  entry_price: Decimal | null
  fraction: Decimal | null
  usd_amount: Decimal | null
  exit_basis: string | null
}

export interface ManualCorrectionRequest {
  correction_id: string
  source_id: string
  selected_account_ids: string[]
  actor: string
  reason: string
  instructions: ManualInstruction[]
}

export interface ManualCorrectionOutcome {
  correction: ManualCorrectionRequest & { revision: number; source_revision: number; source_at: string; source_text: string; recorded_at: string }
  accounts: { account_id: string; status: string; reason: string | null }[]
}

export interface ManualPreviewRequest {
  preview_id: string
  account_id: string
  correction_id: string
  instruction_index: number
}

export interface ManualQuote {
  feed: string
  bid: Decimal | null
  ask: Decimal | null
  timestamp: string | null
}

/** What the order will be, as the engine planned it. The confirmation dialog is built from this. */
export interface ManualOrderPlan {
  side: string
  position_intent: string
  type: string
  limit_price: Decimal | null
  symbol: string
  qty: Decimal
  source_price: Decimal
  entry_tolerance_pct: Decimal
  lot_id: string | null
  entry_price: Decimal
  session: string
  requested_usd: Decimal | null
  budget_usd: Decimal | null
  limited_by: string | null
}

export interface ManualCheck {
  name: string
  status: string
  reason: string | null
}

export interface ManualOrderPreview {
  request: ManualPreviewRequest
  broker_account_id: string
  environment: TradingEnvironment
  correction_revision: number
  source_at: string
  source_age_seconds: number
  instruction: ManualInstruction
  created_at: string
  expires_at: string
  session: string | null
  quote: ManualQuote | null
  fresh_price: Decimal | null
  plan: ManualOrderPlan | null
  limit_price: Decimal | null
  checks: ManualCheck[]
  reasons: string[]
  facts_sha256: string
  configuration_sha256: string
}

export interface ManualConfirmation {
  command_id: string
  preview_id: string
  account_id: string
  actor: string
}

export interface ManualCommandResult {
  command: {
    request: ManualConfirmation
    correction_id: string
    source_id: string
    instruction_index: number
    confirmed_at: string
    state: string
    reason: string | null
    client_id: string | null
  }
  status: string
  reason: string | null
  client_id: string | null
  broker_order_id: string | null
  order_status: string | null
  filled_qty: Decimal
}

export interface ManualCommandPage {
  account_id: string
  source_id: string
  items: ManualCommandResult[]
  next_before_command_id: string | null
}

export interface ManualCommandsOutcome {
  outcomes: { account_id: string; command_id: string; result: ManualCommandResult | null; error: string | null }[]
}

export interface LotSalePreviewRequest {
  preview_id: string
  account_id: string
  lot_id: string
  qty: Decimal
}

export interface LotSalePreview {
  request: LotSalePreviewRequest
  broker_account_id: string
  environment: TradingEnvironment
  symbol: string
  lot_remaining_qty: Decimal
  created_at: string
  expires_at: string
  session: string | null
  quote: ManualQuote | null
  fresh_price: Decimal | null
  plan: ManualOrderPlan | null
  checks: ManualCheck[]
  reasons: string[]
  facts_sha256: string
}

export interface LotSaleConfirmation {
  command_id: string
  preview_id: string
  account_id: string
  actor: string
}

export interface LotSaleResult {
  sale: {
    request: LotSaleConfirmation
    lot_id: string
    confirmed_at: string
    state: string
    reason: string | null
    client_id: string | null
  }
  status: string
  reason: string | null
  client_id: string | null
  broker_order_id: string | null
  order_status: string | null
  filled_qty: Decimal
  filled_avg_price: Decimal | null
}

// ── Account control and ownership ──────────────────────────────────────────

export interface AccountControlCommand {
  command_id: string
  account_id: string
  action: "pause" | "resume"
}

export interface AccountControlResult {
  command: AccountControlCommand
  applied_at: string
  entry_permission: string
  recovery_preference: RecoveryPreference
}

export interface OwnershipResolutionRequest {
  resolution_id: string
  incident_id: string
  account_id: string
  symbol: string
  actor: string
  reason: string
  broker_qty: Decimal
  external_qty: Decimal
  lot_remaining: Record<string, Decimal>
}

export interface OwnershipResolution {
  request: OwnershipResolutionRequest
  checked_at: string
  lot_reductions: Record<string, Decimal>
  allocation_revision: number
}

// ── Guru profiles ──────────────────────────────────────────────────────────

export interface ProfileRevision {
  guru_id: string
  display_name: string
  playbook: string
  profile_revision: string
}

export interface LearnedGuruPlaybook {
  posts_read: number
  playbook: string
  summary: string
  provider: string
  model: string
  cost_notice: string
}

export interface ProfileEvaluation {
  message_identity: string
  guru_id: string
  profile_revision: string
  provider: string
  model: string
  decision: string
  reason: string
  simulated: boolean
  no_order: boolean
  cost_notice: string
  instructions: (SourceInstruction & { action_evidence: string; symbol_evidence: string })[]
  destinations: { account_id: string; action: string; symbol: string; budget_usd: Decimal | null; estimated_quantity: Decimal | null; exit_basis: string | null; reason: string }[]
  review_reasons: string[]
}

// ── Backup and restore ─────────────────────────────────────────────────────

export interface BackupMember {
  path: string
  size: number
  sha256: string
  schema_version: string
}

export interface BackupManifest {
  format_version: number
  created_at: string
  installation_id: string
  environment_ids: string[]
  members: BackupMember[]
}

export interface RestorePreview {
  format_version: number
  created_at: string
  installation_id: string
  matches_installation: boolean
  environment_ids: string[]
  account_ids: string[]
  credential_references: string[]
  staging_id: string
  members: BackupMember[]
}

export interface PendingRestoreCandidate {
  candidate_id: string
  previous_generation: string
  active_generation: string
  installation_id: string
  environment_ids: string[]
  account_ids: string[]
  credential_references: string[]
  candidate_valid: boolean
}

export interface RestorePreflightAccount {
  account_id: string
  environment: TradingEnvironment
  key: string
  secret: string
}

export interface RestorePreflight {
  candidate_id: string
  eligible: boolean
  checked_account_count: number
  blockers: string[]
  completion_token: string | null
}

// ── Agent proposals and the assistant ──────────────────────────────────────

export interface AgentManualOrder {
  account_id: string
  preview_id: string
  environment: TradingEnvironment
  symbol: string
  side: string
  order_type: string
  quantity: Decimal
  limit_price: Decimal | null
}

export type AgentProposalSubject =
  | { kind: "resume_account"; account_id: string }
  | { kind: "set_recovery"; account_id: string; preference: string }
  | ({ kind: "confirm_manual_order" } & AgentManualOrder)
  | { kind: "set_account_limits"; account_id: string; changes: { field: string; value: string }[] }
  | { kind: "start_processing" }
  | { kind: "apply_setup"; [fact: string]: unknown }

export interface AgentProposal {
  proposal_id: string
  state: "pending" | "running" | "succeeded" | "failed" | "outcome_unknown" | "rejected" | "expired" | "discarded"
  subject: AgentProposalSubject
  digest: string
  created_at: string
  expires_at: string
  requested_by: { pid: number | null; path: string | null }
  outcome: { status: string; code: string | null } | null
}

export interface AgentAuditEntry {
  at: string
  actor: string
  caller_pid: number | null
  caller_path: string | null
  operation: string
  tier: string | null
  outcome: string
  proposal_id: string | null
}

export interface AssistantAskContext {
  screen: string
  selected_source_id?: string | null
  selected_account_id?: string | null
  selected_guru_id?: string | null
  language: string
  gurus: { id: string; name: string }[]
  setup?: unknown
}

export interface AssistantTurnPage {
  turn_id: string
  done: boolean
  events: {
    seq: number
    kind: string
    text: string | null
    link: { kind: string; id: string; title: string } | null
    proposal_id: string | null
    code: string | null
  }[]
}

// ── The operations ─────────────────────────────────────────────────────────
// Each entry is [params, result]. `undefined` params means none; `X | undefined` means optional.

type Op<P, R> = [params: P, result: R]

export interface ReadOperations {
  // Engine
  getStatus: Op<undefined, TradingStatus>
  getEngineStatus: Op<undefined, EngineStatus>
  getTradingActivation: Op<{ activation_id: string }, TradingActivationStatus>
  getWorkflow: Op<{ command_id: string }, WorkflowView>
  getAccounts: Op<undefined, AccountOverviewPage>
  getEquityHistory: Op<{ account_id: string; range: HistoryRange; day?: string }, EquityHistory | null>
  getSourceActivity: Op<{ before_seq?: number; limit?: number } | undefined, SourceActivityPage>
  getGuruActivity: Op<{ guru_id: string; before_seq?: number; limit?: number }, SourceActivityPage>
  getGuruDayStats: Op<{ day_start: string; day_end: string }, GuruDayStatsPage>
  getAccountFeed: Op<{ account_id: string; before_seq?: number; limit?: number }, AccountFeedPage>
  getQuote: Op<{ account_id: string; symbol: string }, MarketQuote | null>
  getManualCommand: Op<{ account_id: string; command_id: string }, ManualCommandResult>
  listManualCommands: Op<{ account_id: string; source_id: string; before_command_id?: string; limit?: number }, ManualCommandPage>
  /** Plans an order and keeps what it planned; `confirmManualOrders` asks about that plan. */
  previewManualOrder: Op<{ preview: ManualPreviewRequest }, ManualOrderPreview>
  /** Plans a sale of part of a lot and keeps what it planned; `confirmLotSale` asks about that plan. */
  previewLotSale: Op<{ preview: LotSalePreviewRequest }, LotSalePreview>
  listProposals: Op<undefined, AgentProposal[]>
  getAgentAudit: Op<{ limit?: number } | undefined, AgentAuditEntry[]>
  getRestoreCandidate: Op<undefined, PendingRestoreCandidate | null>
  getAssistantTurn: Op<{ turn_id: string; after: number }, AssistantTurnPage>
  // Main process: the saved setup and the key store
  getSetup: Op<undefined, SetupView | null>
  getLimits: Op<{ account_id: string }, AccountLimits | null>
  getSecretStatus: Op<undefined, SecretStatus>
}

export interface ActOperations {
  // Each of these shows a native confirmation, built by main from its own data, before the engine hears of it
  // (down to updateAccountLimits).
  confirmManualOrders: Op<{ commands: ManualConfirmation[] }, ManualCommandsOutcome>
  confirmLotSale: Op<{ sale: LotSaleConfirmation }, LotSaleResult>
  /** Starts the saved setup; `validate` first, then `saveSetup` with its revision. */
  startTrading: Op<{ activation_id: string; validation_token: string }, TradingStatus>
  pauseTrading: Op<undefined, TradingStatus>
  controlAccount: Op<{ command: AccountControlCommand }, AccountControlResult>
  approveProposal: Op<{ proposal_id: string }, AgentProposal>
  deleteAccountRecord: Op<{ account_id: string }, null>
  completeRestoreCandidate: Op<{ candidate_id: string; completion_token: string }, null>
  /** Gives copying new account limits at once, and saves them in the setup file under the engine's revision. The dialog lists each change. */
  updateAccountLimits: Op<{ configuration: TradingConfiguration }, { revision: string }>
  // No confirmation below: none places an order or changes what copying does. A start still needs `startTrading`.
  validateTrading: Op<{ configuration: TradingConfiguration }, TradingValidation>
  checkConnection: Op<{ connection: ConnectionCheck }, CapabilityCheck>
  /** Saves a validated setup; refused unless copying is paused. */
  saveSetup: Op<{ configuration: TradingConfiguration; revision: string }, null>
  setSecrets: Op<SecretUpdate, SecretStatus>
  forgetBroker: Op<{ account_id: string }, SecretStatus>
  createBackup: Op<{ destination: string }, BackupManifest>
  previewRestore: Op<{ archive_path: string }, RestorePreview>
  prepareRestoreCandidate: Op<{ staging_id: string }, { candidate_id: string }>
  abortRestoreCandidate: Op<{ candidate_id: string }, null>
  restorePreflight: Op<{ candidate_id: string; accounts: RestorePreflightAccount[] }, RestorePreflight>
  resolveOwnership: Op<{ account_id: string; resolution: OwnershipResolutionRequest }, OwnershipResolution>
  saveManualCorrection: Op<{ correction: ManualCorrectionRequest }, ManualCorrectionOutcome>
  rejectProposal: Op<{ proposal_id: string }, AgentProposal>
  completeProposal: Op<{ proposal_id: string; outcome: "succeeded" | "failed"; code?: string }, AgentProposal>
  discardProposals: Op<undefined, { count: number }>
  learnGuruPlaybook: Op<{ channel_id: string; author_id?: string; provider: TradingProvider }, LearnedGuruPlaybook>
  evaluateHistoricalProfile: Op<
    { source_id: string; profile: ProfileRevision; provider: TradingProvider; destinations: { account_id: string; full_position_usd: string }[] },
    ProfileEvaluation
  >
  assistantAsk: Op<{ conversation_id: string; text: string; context: AssistantAskContext; provider: TradingProvider }, { turn_id: string }>
  assistantCancel: Op<{ turn_id: string }, { cancelled: boolean }>
  assistantReset: Op<undefined, null>
  submitSelfTest: Op<{ command: { command_id: string; text: string; destination_ids: string[] } }, WorkflowView>
}

/** Engine operations only main sends: lifecycle, the agent socket relay, and the paused-account readers. */
export const MAIN_ONLY = ["stop", "control", "authorize_setup", "attach_account_readers", "detach_account_readers"] as const

export type ReadName = keyof ReadOperations
export type ActName = keyof ActOperations

// The names the preload builds its methods from; `satisfies` keeps them equal to the keys above.
export const READS = [
  "getStatus", "getEngineStatus", "getTradingActivation", "getWorkflow", "getAccounts", "getEquityHistory",
  "getSourceActivity", "getGuruActivity", "getGuruDayStats", "getAccountFeed", "getQuote", "getManualCommand",
  "listManualCommands", "previewManualOrder", "previewLotSale", "listProposals", "getAgentAudit",
  "getRestoreCandidate", "getAssistantTurn", "getSetup", "getLimits", "getSecretStatus",
] as const satisfies readonly ReadName[]

export const ACTS = [
  "confirmManualOrders", "confirmLotSale", "startTrading", "pauseTrading", "controlAccount", "approveProposal",
  "deleteAccountRecord", "completeRestoreCandidate", "validateTrading", "checkConnection", "updateAccountLimits",
  "saveSetup", "setSecrets", "forgetBroker", "createBackup", "previewRestore", "prepareRestoreCandidate",
  "abortRestoreCandidate", "restorePreflight", "resolveOwnership", "saveManualCorrection", "rejectProposal",
  "completeProposal", "discardProposals", "learnGuruPlaybook", "evaluateHistoricalProfile", "assistantAsk",
  "assistantCancel", "assistantReset", "submitSelfTest",
] as const satisfies readonly ActName[]

// Compile-time check that the lists are complete: a name missing from READS or ACTS is a type error here.
type Missing<Names extends string, List extends string> = Exclude<Names, List>
export const _complete: [Missing<ReadName, (typeof READS)[number]>, Missing<ActName, (typeof ACTS)[number]>] extends [never, never] ? true : never = true

type Args<P> = undefined extends P ? [params?: P] : [params: P]
type Call<O extends [unknown, unknown]> = (...args: Args<O[0]>) => Promise<Result<O[1]>>

export type ReadApi = { [K in ReadName]: Call<ReadOperations[K]> }
export type ActApi = { [K in ActName]: Call<ActOperations[K]> }

/** `window.copytrading`: everything the renderer may do. No ipcRenderer, no raw engine pipe. */
export interface DesktopApi {
  read: ReadApi
  act: ActApi
  engine: {
    state(): Promise<EngineState>
    /** Calls `listener` on every change; returns the way to stop. */
    onState(listener: (state: EngineState) => void): () => void
  }
}

export const CHANNELS = { read: "engine:read", act: "engine:act", state: "engine:state", stateChanged: "engine:state-changed" } as const
