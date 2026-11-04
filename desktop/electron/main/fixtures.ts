import type { AccountOverview, EquityHistory, HistoryRange, Result } from "../../shared/contract"
import type { Api } from "./api"
import { setupReads } from "./fixtures-setup"
import account from "./fixtures/account.json"
import history from "./fixtures/history.json"
import { peopleReads } from "./fixtures/people"
import positions from "./fixtures/positions.json"
import { settingsActs, settingsReads } from "./fixtures/settings"

export { seedFixturePictures } from "./fixtures/people"

// Real zhap-account-2 data, captured Nov 3, served in the engine's wire shape so the renderer
// runs the same adapters in fixture mode as against a live engine.

const POSTED = { SOXL: "2026-10-22T16:00:00Z", SOXS: "2026-10-22T16:00:00Z" } as Record<string, string>
const lots = account.lots as Record<string, { guru: string }>

// COPYTRADING_FIXTURE_SCENE=attention serves the states the captured account never had, for `npm run capture`:
// the engine could not keep the account, and its SOXL holds shares CopyTrading did not buy.
const attention = process.env.COPYTRADING_FIXTURE_SCENE === "attention"

const overview: AccountOverview = {
  account_id: account.account_id,
  environment: "paper",
  entry_permission: "enabled",
  active_configuration: true,
  readiness: attention ? "broker_keys_rejected" : "enabled",
  ownership_incidents: attention
    ? [{ incident_id: "incident-soxl", symbol: "SOXL", expected_qty: "6.679793", actual_qty: "10", observed_at: "2026-11-03T20:00:00Z", cause: "broker_quantity_differs" }]
    : [],
  total_exposure_usd: account.total_exposure_usd,
  pending_orders: account.pending_orders,
  balance: { ...account.balance, previous_close_equity: "2715.27" },
  positions: positions.map((p) => ({
    symbol: p.symbol,
    owned_qty: p.qty,
    broker_qty: attention && p.symbol === "SOXL" ? "10" : p.qty,
    lots: lots[p.symbol]
      ? [{ lot_id: `lot-${p.symbol}`, guru_id: lots[p.symbol]!.guru, posted_at: POSTED[p.symbol] ?? null, remaining_qty: p.qty, average_price: p.avg_entry_price, bought_at: POSTED[p.symbol] ?? null, unrealized_pl: p.unrealized_pl }]
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
  getLimits: () => ok(limits),
  ...peopleReads,
  ...settingsReads,
  ...setupReads,
  // A quote from just before the pinned clock, so Market reads live.
  getQuote: () => ok({ feed: "iex", bid: "40.40", ask: "40.45", timestamp: "2026-11-03T20:59:30Z" }),
}

const ACTS: Record<string, (params: Params) => Promise<Result<unknown>>> = { ...settingsActs }

const notCaptured = async (name: string): Promise<Result<never>> => ({ ok: false, error: `${name} is not in the captured fixtures.` })

export const fixtureApi: Api = {
  read: (name, params) => (typeof name === "string" && READS[name] ? READS[name](params as Params) : notCaptured(String(name))),
  act: (name, params) => (typeof name === "string" && ACTS[name] ? ACTS[name](params as Params) : notCaptured(String(name))),
}
