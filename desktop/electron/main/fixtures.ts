import type { AccountOverview, Bar, EquityHistory, GuruPerformance, HistoryRange, Result } from "../../shared/contract"
import type { Api } from "./api"
import { setupReads } from "./fixtures-setup"
import account from "./fixtures/account.json"
import bars from "./fixtures/bars.json"
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
  positions: (process.env.COPYTRADING_FIXTURE_SCENE === "empty" ? [] : positions).map((p) => ({
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

// Only in a build made with `electron-vite build --mode tick` (or `dev --mode tick`) and COPYTRADING_FIXTURE_TICK=1: every
// read of the accounts moves the balance, a gain, a loss, a big swing, so the rolling figures can be watched and captured.
// A normal build's mode is "production" or "development", so the bundler drops this and the table: the app never has it.
const TICKS = import.meta.env.MODE === "tick" && process.env.COPYTRADING_FIXTURE_TICK === "1" ? [37.42, -112.9, 1204.5, -1500.25, 8.01] : []
let ticked = 0
let quoted = 0
const shift = (value: string, by: number) => (Number(value) + by).toFixed(2)
function accountsNow(): AccountOverview {
  if (TICKS.length === 0) return overview
  const by = TICKS[ticked++ % TICKS.length]!
  const b = overview.balance!
  overview.balance = { ...b, equity: shift(b.equity, by), day_change_usd: shift(b.day_change_usd, by), cash: shift(b.cash, by), buying_power: shift(b.buying_power, by) }
  return overview
}

const HISTORY_KEY: Record<HistoryRange, keyof typeof history | null> = {
  day: "1D",
  week: "1W",
  month: "1M",
  three_months: "3M",
  year: null,
}

// Records left from earlier runs: not in the saved setup, so Settings lists them under "Old records".
const oldRecords: AccountOverview[] = ["testing", "primary", "jean-testing"].map((id) => ({
  account_id: id,
  environment: "paper",
  entry_permission: "enabled",
  total_exposure_usd: null,
  pending_orders: null,
  balance: null,
  positions: [],
}))
// COPYTRADING_FIXTURE_SCENE=records serves them beside the live account; COPYTRADING_FIXTURE_STATE=accounts-error
// fails the accounts read, accounts-loading answers it after two minutes.
const records = process.env.COPYTRADING_FIXTURE_SCENE === "records"
const accountsState = process.env.COPYTRADING_FIXTURE_STATE

// SOXL's and SOXS's real five-minute IEX bars of Nov 4, read through AlpacaBroker.bars (the engine's get_bars).
const barsBySymbol = bars as Record<string, Bar[]>

// A guru with no closed trades answers its empty state. COPYTRADING_FIXTURE_SCENE=performance serves SYNTHETIC figures
// (not captured: the captured account has no replayed sales) so the card can be captured with a line, a best and a worst call.
const performanceScene = process.env.COPYTRADING_FIXTURE_SCENE === "performance"
const closed = (symbol: string, profit: string, day: string, excerpt: string) => ({ symbol, profit_usd: profit, closed_on: day, source_id: `discord:1100000000000000001:${symbol}`, excerpt, posted_at: `${day}T15:00:00Z` })
// The second guru (赵哥-加密) is down, so the Gurus list has a leader and a laggard to rank.
const performance = (guru_id: string, account_id: string): GuruPerformance =>
  performanceScene && guru_id === "赵哥-加密"
    ? {
        guru_id,
        account_id,
        realized_usd: "-41.15",
        unrealized_usd: "-6.80",
        closed_trades: 5,
        winning_trades: 2,
        unmatched_sells: 0,
        best: closed("BTCU", "12.40", "2026-10-29", "BTCU 加 25"),
        worst: closed("ETHU", "-38.90", "2026-11-02", "ETHU 减 10"),
        series: [
          { day: "2026-10-27", cumulative_usd: "-4.10" },
          { day: "2026-10-29", cumulative_usd: "8.30" },
          { day: "2026-10-31", cumulative_usd: "-12.60" },
          { day: "2026-11-02", cumulative_usd: "-50.30" },
          { day: "2026-11-03", cumulative_usd: "-41.15" },
        ],
      }
    : performanceScene
    ? {
        guru_id,
        account_id,
        realized_usd: "63.40",
        unrealized_usd: "-18.25",
        closed_trades: 5,
        winning_trades: 4,
        unmatched_sells: 0,
        best: closed("SOXL", "52.10", "2026-10-30", "SOXL 加 40.2"),
        worst: closed("SOXS", "-14.30", "2026-11-03", "SOXS 减 8.5"),
        series: [
          { day: "2026-10-27", cumulative_usd: "8.20" },
          { day: "2026-10-28", cumulative_usd: "21.70" },
          { day: "2026-10-29", cumulative_usd: "15.10" },
          { day: "2026-10-30", cumulative_usd: "67.20" },
          { day: "2026-11-03", cumulative_usd: "63.40" },
        ],
      }
    : { guru_id, account_id, realized_usd: "0", unrealized_usd: "0", closed_trades: 0, winning_trades: 0, unmatched_sells: 0, best: null, worst: null, series: [] }

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
  getAccounts: () =>
    accountsState === "accounts-error"
      ? Promise.resolve<Result<never>>({ ok: false, error: "The engine did not answer the accounts request." })
      : accountsState === "accounts-loading"
        ? new Promise<Result<never>>((done) => setTimeout(() => done({ ok: false, error: "The engine did not answer the accounts request." }), 120_000))
        : ok({ items: records ? [...oldRecords, accountsNow()] : [accountsNow()], unavailable_accounts: [] }),
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
  getBars: (params) => ok(Object.fromEntries(((params?.symbols as string[]) ?? []).map((symbol) => [symbol, barsBySymbol[symbol] ?? []]))),
  getGuruPerformance: (params) => ok(performance(String(params?.guru_id), String(params?.account_id))),
  // A quote from just before the pinned clock, so Market reads live.
  // In a tick build the quote moves up and down on each ask, so a held row's live price can be watched.
  getQuote: () => {
    const by = TICKS.length ? [0.35, -0.5, 0.9][quoted++ % 3]! : 0
    return ok({ feed: "iex", bid: (40.4 + by).toFixed(2), ask: (40.45 + by).toFixed(2), timestamp: "2026-11-03T20:59:30Z" })
  },
}

const ACTS: Record<string, (params: Params) => Promise<Result<unknown>>> = { ...settingsActs }

const notCaptured = async (name: string): Promise<Result<never>> => ({ ok: false, error: `${name} is not in the captured fixtures.` })

// COPYTRADING_FIXTURE_STATE=reads-error makes every read fail, reads-loading makes every read wait forever, for the capture of those states.
const readsState = process.env.COPYTRADING_FIXTURE_STATE
const failing = async (): Promise<Result<never>> => ({ ok: false, error: "The engine did not answer in time. Check that it is running, then try again." })

// COPYTRADING_FIXTURE_STATE=figures-error / figures-loading fail or hold only today's counts and the performance, so a list of gurus shows its figures failed or loading.
const FIGURES = ["getGuruDayStats", "getGuruPerformance"]
const figuresState = readsState === "figures-error" || readsState === "figures-loading" ? readsState : null

export const fixtureApi: Api = {
  read: (name, params) =>
    figuresState && FIGURES.includes(String(name))
      ? figuresState === "figures-error"
        ? failing()
        : new Promise<never>((_, reject) => setTimeout(() => reject(new Error("never answered")), 10 * 60_000))
      : readsState === "reads-error"
      ? failing()
      : readsState === "reads-loading"
        ? new Promise<never>((_, reject) => setTimeout(() => reject(new Error("never answered")), 10 * 60_000))
        : typeof name === "string" && READS[name]
          ? READS[name](params as Params)
          : notCaptured(String(name)),
  act: (name, params) => (typeof name === "string" && ACTS[name] ? ACTS[name](params as Params) : notCaptured(String(name))),
}
