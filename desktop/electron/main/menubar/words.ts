import type { AccountOverview, EngineState, MenuBarMode, SourceActivity, TradingStatus } from "../../../shared/contract"
import { COPYING_STATES, type Tone } from "../../../shared/copying-state"
import { filledUsd, num } from "@/features/activity/amounts"
import { openCall } from "@/features/account/waiting"
import { money, signedMoney, signedPercent, timeOfDay } from "@/lib/format"

// What the menu bar item says, decided from what the window reads (status, accounts, posts). Pure: the tray draws it.

export interface Reading {
  engine: EngineState
  status: TradingStatus | null
  accounts: AccountOverview[]
  posts: SourceActivity[]
  /** The ids the window says were skipped; null until it has said (the count is then left out, not guessed). */
  skipped: ReadonlySet<string> | null
  now: Date
}

/** The dot: the sidebar footer's own tones, with a stopped or unreachable engine red. */
export function tone({ engine, status }: Pick<Reading, "engine" | "status">): Tone {
  if (engine.state === "stopped") return "destructive"
  if (engine.state === "starting") return "warning"
  return status ? COPYING_STATES[status.state].tone : "idle"
}

/** What an account list adds up to: the balance, and today's change from yesterday's close. */
function totals(accounts: AccountOverview[]) {
  const held = accounts.flatMap((a) => (a.balance ? [a.balance] : []))
  if (held.length === 0) return null
  const equity = held.reduce((sum, b) => sum + Number(b.equity), 0)
  const change = held.reduce((sum, b) => sum + Number(b.day_change_usd), 0)
  const close = held.reduce((sum, b) => sum + Number(b.previous_close_equity), 0)
  return { equity, change, fraction: close > 0 ? change / close : 0 }
}

/** "$2,681 ▼0.4%": whole dollars, and a triangle for the direction. */
export function title(accounts: AccountOverview[]): string {
  const t = totals(accounts)
  if (!t) return ""
  const whole = Math.round(t.equity).toLocaleString("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 })
  const arrow = Math.abs(t.fraction) < 0.0005 ? "" : t.fraction > 0 ? "▲" : "▼"
  return `${whole} ${arrow}${Math.abs(t.fraction * 100).toFixed(1)}%`
}

/** "Bought $99.94 of SOXL, 9:20 AM": the newest copied order that filled, or null. The owner's own sales are not copies. */
export function lastTrade(posts: SourceActivity[]): string | null {
  let newest: { text: string; at: number } | null = null
  for (const post of posts) {
    for (const destination of post.destinations) {
      for (const order of destination.orders ?? []) {
        const filled = num(order.filled_quantity)
        const stamp = order.ended_at ?? order.submitted_at
        if (!filled || filled <= 0 || !stamp || order.client_id.startsWith("lotsale-")) continue
        const at = Date.parse(stamp)
        if (newest && at <= newest.at) continue
        const used = filledUsd(order)
        const verb = order.side === "sell" ? "Sold" : "Bought"
        newest = { at, text: `${verb} ${used === null ? "" : `${money(used)} of `}${order.symbol}, ${timeOfDay(stamp)}` }
      }
    }
  }
  return newest?.text ?? null
}

/** The first account with a call waiting for the owner, and how many posts wait; null while the skipped list is unknown. */
export function waiting({ posts, skipped, now }: Pick<Reading, "posts" | "skipped" | "now">): { count: number; accountId: string | null } | null {
  if (!skipped) return null
  const calls = posts.flatMap((post) => openCall(post, { skipped: skipped.has(post.source_id ?? String(post.sequence)), now }) ?? [])
  return { count: calls.length, accountId: calls[0]?.accountIds[0] ?? null }
}

export type MenuAction = "waiting" | "pause" | "start" | "open" | "quit"
export type Item = { type: "separator" } | { label: string; enabled?: boolean; action?: MenuAction }

export interface View {
  /** The text beside the dot, empty for "Dot only". */
  title: string
  tone: Tone
  items: Item[]
  /** The account page "N waiting for you" opens. */
  waitingRoute: string | null
}

/** The item and its menu, from one reading. */
export function view(reading: Reading, mode: MenuBarMode): View {
  const { engine, status, accounts } = reading
  const t = totals(accounts)
  const wait = waiting(reading)
  const trade = lastTrade(reading.posts)
  const state = status ? COPYING_STATES[status.state] : null
  const copying = status?.state === "running" || status?.state === "degraded"
  const pending = engine.state === "starting" || status?.state === "starting" || status?.state === "pausing"
  const toggle: Item = copying
    ? { label: "Pause Copying", action: "pause" }
    : pending || engine.state !== "running" || !status
      ? { label: status?.state === "pausing" ? "Pausing…" : "Start Copying", enabled: false }
      : { label: "Start Copying", action: "start" }
  const headline = engine.state === "stopped" ? "Engine stopped" : engine.state === "starting" ? "Engine starting" : (state?.label ?? "Checking the engine")
  return {
    title: mode === "balance" ? title(accounts) : "",
    tone: tone(reading),
    waitingRoute: wait?.accountId ? `#/accounts/${encodeURIComponent(wait.accountId)}` : null,
    items: [
      { label: headline, enabled: false },
      ...(t ? [{ label: `Today ${signedMoney(t.change)} (${signedPercent(t.fraction)})`, enabled: false }] : []),
      ...(trade ? [{ label: trade, enabled: false }] : []),
      { type: "separator" },
      ...(wait && wait.count > 0 ? [{ label: `${wait.count} waiting for you`, action: "waiting" as const }, { type: "separator" as const }] : []),
      toggle,
      { label: "Open CopyTrading", action: "open" },
      { type: "separator" },
      { label: "Quit CopyTrading", action: "quit" },
    ],
  }
}
