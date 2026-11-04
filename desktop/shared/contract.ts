// What crosses the preload bridge: the engine's replies, narrowed to the fields the app reads.
// Money and share counts arrive as decimal strings (pydantic JSON mode); format.ts parses them.

export type Decimal = string

export type Result<T> = { ok: true; value: T } | { ok: false; error: string }

export type TradingRunState = "paused" | "starting" | "running" | "degraded" | "pausing" | "failed"

export interface TradingStatus {
  state: TradingRunState
  configured_accounts: number
  active_accounts: number
  source_connected: boolean
  model_ready: boolean
  error_code: string | null
}

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
}

export interface Position {
  symbol: string
  owned_qty: Decimal
  lots: PositionLot[]
  avg_entry_price: Decimal | null
  current_price: Decimal | null
  market_value: Decimal | null
  unrealized_pl: Decimal | null
  unrealized_plpc: Decimal | null
}

export interface AccountOverview {
  account_id: string
  environment: "paper" | "live"
  entry_permission: string
  total_exposure_usd: Decimal | null
  positions: Position[]
  pending_orders: number | null
  balance: AccountBalance | null
}

export interface AccountOverviewPage {
  items: AccountOverview[]
  unavailable_accounts: { account_id: string; reason: string }[]
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
}

export interface SourceActivity {
  sequence: number
  source_at: string
  /** Untrusted Discord text: render it as text, never as HTML. */
  text: string
  decision: "trade" | "review" | "ignore" | null
  guru_id: string | null
  instructions: SourceInstruction[]
  destinations: { account_id: string; status: string; instruction_outcomes: string[] }[]
}

export interface SourceActivityPage {
  items: SourceActivity[]
}

/** The owner's saved limits for one account; they live in the app's setup, not the engine. */
export interface AccountLimits {
  guru: string
  full_position_usd: number
  daily_loss_cap_usd: number
  max_total_usd: number
  max_order_usd: number
  max_symbol_usd: number
  max_entries_per_day: number
}

export interface DesktopApi {
  getStatus(): Promise<Result<TradingStatus>>
  getAccounts(): Promise<Result<AccountOverviewPage>>
  getEquityHistory(accountId: string, range: HistoryRange): Promise<Result<EquityHistory | null>>
  getSourceActivity(): Promise<Result<SourceActivityPage>>
  getLimits(accountId: string): Promise<Result<AccountLimits | null>>
}

export const CHANNELS = {
  getStatus: "engine:get-status",
  getAccounts: "engine:get-accounts",
  getEquityHistory: "engine:get-equity-history",
  getSourceActivity: "engine:get-source-activity",
  getLimits: "engine:get-limits",
} as const
