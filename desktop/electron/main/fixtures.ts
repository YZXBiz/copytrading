import type { AccountOverview, EquityHistory, HistoryRange, Result, SourceActivity } from "../../shared/contract"
import type { Api } from "./api"
import account from "./fixtures/account.json"
import activity from "./fixtures/activity.json"
import history from "./fixtures/history.json"
import positions from "./fixtures/positions.json"

// Real zhap-account-2 data, captured Nov 3, served in the engine's wire shape so the renderer
// runs the same adapters in fixture mode as against a live engine.

const POSTED = { SOXL: "2026-10-22T16:00:00Z", SOXS: "2026-10-22T16:00:00Z" } as Record<string, string>
const lots = account.lots as Record<string, { guru: string }>

const overview: AccountOverview = {
  account_id: account.account_id,
  environment: "paper",
  entry_permission: "enabled",
  total_exposure_usd: account.total_exposure_usd,
  pending_orders: account.pending_orders,
  balance: { ...account.balance, previous_close_equity: "2715.27" },
  positions: positions.map((p) => ({
    symbol: p.symbol,
    owned_qty: p.qty,
    lots: lots[p.symbol]
      ? [{ lot_id: `lot-${p.symbol}`, guru_id: lots[p.symbol]!.guru, posted_at: POSTED[p.symbol] ?? null, remaining_qty: p.qty }]
      : [],
    avg_entry_price: p.avg_entry_price,
    current_price: p.current_price,
    market_value: p.market_value,
    unrealized_pl: p.unrealized_pl,
    unrealized_plpc: p.unrealized_plpc,
  })),
}

const HISTORY_KEY: Record<HistoryRange, keyof typeof history | null> = {
  day: "1D",
  week: "1W",
  month: "1M",
  three_months: "3M",
  year: null,
}

const posts: SourceActivity[] = activity.map((a, index) => ({
  sequence: activity.length - index,
  source_at: a.at,
  text: a.text,
  decision: a.decision as SourceActivity["decision"],
  guru_id: "赵哥",
  instructions:
    a.decision === "trade" ? [{ action: "close", symbol: "AEHR", price: "61.50" }] : [],
  destinations:
    a.decision === "trade"
      ? [{ account_id: account.account_id, status: "delivered", instruction_outcomes: ["no_open_lot"] }]
      : a.decision === "review"
        ? [{ account_id: account.account_id, status: "review_required", instruction_outcomes: [] }]
        : [],
}))

const delay = <T>(value: T) => new Promise<T>((done) => setTimeout(() => done(value), 150))
const ok = async <T>(value: T): Promise<Result<T>> => ({ ok: true, value: await delay(value) })

const limits = {
  guru: "赵哥",
  full_position_usd: 1000,
  daily_loss_cap_usd: account.limits.daily_loss_cap_usd,
  max_total_usd: account.limits.max_total_usd,
  max_order_usd: account.limits.max_order_usd,
  max_symbol_usd: account.limits.max_symbol_usd,
  max_entries_per_day: account.limits.max_entries_per_day,
}

type Params = Record<string, unknown> | undefined

// Only what the account page reads is captured; every other operation says so instead of inventing data.
const READS: Record<string, (params: Params) => Promise<Result<unknown>>> = {
  getStatus: () =>
    ok({ state: "running", configured_accounts: 1, active_accounts: 1, source_connected: true, model_ready: true, error_code: null }),
  getAccounts: () => ok({ items: [overview], unavailable_accounts: [] }),
  getEquityHistory: (params) => {
    const key = HISTORY_KEY[params?.range as HistoryRange]
    const value: EquityHistory | null = key
      ? {
          base_value: String(history[key][0]?.v ?? ""),
          points: history[key].map((p) => ({ at: new Date(p.t * 1000).toISOString(), equity: String(p.v) })),
        }
      : null
    return ok(value)
  },
  getSourceActivity: () => ok({ items: posts }),
  getLimits: () => ok(limits),
}

const notCaptured = async (name: string): Promise<Result<never>> => ({ ok: false, error: `${name} is not in the captured fixtures.` })

export const fixtureApi: Api = {
  read: (name, params) => (typeof name === "string" && READS[name] ? READS[name](params as Params) : notCaptured(String(name))),
  act: (name) => notCaptured(String(name)),
}
