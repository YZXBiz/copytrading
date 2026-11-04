import type { DestinationActivity, SourceActivity, SourceInstruction } from "../../../shared/contract"
import { monthDay } from "@/lib/format"
import { reasonText } from "./reasons"

// A post that waits for the owner (ADR-0007), as WaitingCall.swift decides: an account holds its call, its
// trading day is not over, and the owner has neither skipped it nor entered the trade by hand.

/** A sell held because none of the account's buys is at the price it names (ADR-0010). The contract does not list it yet. */
export interface NamedBuy {
  part: number
  posted_at: string | null
  /** "sold", "not_filled", or the reason the buy was refused; null when it never reached the account. */
  outcome: string | null
}
type Destination = DestinationActivity & { named_buys?: NamedBuy[] }

/** Skips that hold a call back for the owner rather than refuse it: the engine's HELD_FOR_OWNER. */
const HELD_FOR_OWNER = new Set(["approval_required", "named_buy_not_held"])

export interface WaitingCall {
  source: SourceActivity
  /** The accounts waiting on it. */
  accountIds: string[]
  /** What Copy places: the calls the reader suggests, or the calls an account held back. */
  calls: SourceInstruction[]
  /** Every account waits only because it asked to approve each order, so the owner approves rather than copies. */
  awaitsApproval: boolean
}

/** The waiting call in a post, or null when no account waits on it. */
export function waitingCall(source: SourceActivity): WaitingCall | null {
  const accounts: string[] = []
  const held = new Set<number>()
  let onlyApprovals = true
  for (const destination of source.destinations) {
    const parts = destination.instruction_outcomes.flatMap((o, i) => (HELD_FOR_OWNER.has(o) ? [i] : []))
    const review = destination.status === "review_required"
    if (review || parts.length) {
      accounts.push(destination.account_id)
      if (review || parts.some((i) => destination.instruction_outcomes[i] !== "approval_required")) onlyApprovals = false
    }
    if (review) source.instructions.forEach((_, i) => held.add(i))
    parts.forEach((i) => held.add(i))
  }
  if (!accounts.length) return null
  const suggested = source.suggested ?? []
  return {
    source,
    accountIds: accounts.sort(),
    calls: suggested.length ? suggested : source.instructions.filter((_, i) => held.has(i)),
    awaitsApproval: onlyApprovals,
  }
}

/** The owner placed a trade for this post by hand, so it no longer waits for them. */
const enteredByOwner = (source: SourceActivity) =>
  source.destinations.some((d) => d.orders?.some((o) => o.client_id.startsWith("manual-")))

/** The call a post holds for the owner right now, or null: the one rule for whether a post waits. */
export function openCall(source: SourceActivity, { skipped, now }: { skipped: boolean; now: Date }): WaitingCall | null {
  const call = waitingCall(source)
  return call && !skipped && !hasExpired(source, now) && !enteredByOwner(source) ? call : null
}

/** Whether a post waits, not counting the owner's own skips and hand-entered trades (which live in the app). */
export const isWaiting = (post: SourceActivity, now: Date) => waitingCall(post) !== null && !hasExpired(post, now)

const NEW_YORK = new Intl.DateTimeFormat("en-US", {
  timeZone: "America/New_York",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  hourCycle: "h23",
})

function newYork(instant: Date) {
  return Object.fromEntries(NEW_YORK.formatToParts(instant).map((part) => [part.type, Number(part.value)])) as Record<
    "year" | "month" | "day" | "hour",
    number
  >
}

/** The New York trading day an instant belongs to; from 20:00 it is the next day's, as the engine's `trade_date` counts it. */
export function tradingDay(instant: Date): string {
  const { year, month, day, hour } = newYork(instant)
  return new Date(Date.UTC(year, month - 1, day + (hour >= 20 ? 1 : 0))).toISOString().slice(0, 10)
}

/** Whether the post's trading day has ended, after which it can no longer be copied. */
export const hasExpired = (source: SourceActivity, now: Date) => tradingDay(new Date(source.source_at)) !== tradingDay(now)

/** 20:00 New York time on the trading day the post belongs to. */
export function deadline(source: SourceActivity): Date {
  const day = tradingDay(new Date(source.source_at))
  // New York is 4 or 5 hours behind UTC; the candidate that reads 20:00 there is the deadline.
  const [year, month, date] = day.split("-").map(Number) as [number, number, number]
  const at = (offset: number) => new Date(Date.UTC(year, month - 1, date, 20 + offset))
  const wall = (instant: Date) => {
    const { hour, day: d } = newYork(instant)
    return hour === 20 && d === date
  }
  return wall(at(4)) ? at(4) : at(5)
}

/** "Deadline today: 8:00 PM ET", "tomorrow", or "Fri 8:00 PM ET" further out, on the New York clock. */
export function deadlineText(at: Date, now: Date): string {
  const clock = at.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit", timeZone: "America/New_York" })
  const date = (instant: Date) => {
    const { year, month, day } = newYork(instant)
    return Date.UTC(year, month - 1, day)
  }
  const days = (date(at) - date(now)) / 86_400_000
  if (days <= 0) return `Deadline today: ${clock} ET`
  if (days === 1) return `Deadline tomorrow: ${clock} ET`
  return `Deadline ${at.toLocaleDateString("en-US", { weekday: "short", timeZone: "America/New_York" })} ${clock} ET`
}

/** "15h 20m": how long a post has waited. */
export function waited(posted: string, now: Date): string {
  const minutes = Math.max(0, Math.floor((now.getTime() - new Date(posted).getTime()) / 60_000))
  return minutes < 60 ? `${minutes}m` : `${Math.floor(minutes / 60)}h ${minutes % 60}m`
}

const SHARES: [string, string][] = [
  ["0.75", "¾"],
  ["0.6666666666666666666666666666666666666667", "⅔"],
  ["0.5", "½"],
  ["0.3333333333333333333333333333333333333333", "⅓"],
  ["0.25", "¼"],
  ["0.1666666666666666666666666666666666666667", "⅙"],
]

/** A share of a position as a glyph when it is a usual one ("0.5" → "½"), else a percent. */
export function shareGlyph(fraction: string): string {
  const n = Number(fraction)
  const known = SHARES.find(([text]) => Math.abs(Number(text) - n) < 1e-9)
  return known ? known[1] : `${Math.round(n * 100)}%`
}

/** "Buy SOXS at $40.45", "Sell all AEHR at $61.50", "Sell ½ of WMT". */
export function callPhrase(call: SourceInstruction): string {
  const price = call.price ? ` at $${Number(call.price).toFixed(2)}` : ""
  if (call.action === "buy") return `Buy ${call.symbol}${price}`
  if (call.action === "close" || Number(call.fraction) === 1) return `Sell all ${call.symbol}${price}`
  return `Sell ${call.fraction ? `${shareGlyph(call.fraction)} of ` : ""}${call.symbol}${price}`
}

/** A sell's gain against the buy it names, "+25.0% from $64,603.77", or null when it is not a priced sell. */
export function gainLine(call: SourceInstruction): { change: number; line: string } | null {
  const price = Number(call.price)
  const entry = Number(call.entry_price)
  if (call.action === "buy" || !(price > 0) || !(entry > 0)) return null
  const change = (price - entry) / entry
  const sign = change >= 0 ? "+" : "−"
  return {
    change,
    line: `${sign}${Math.abs(change * 100).toFixed(1)}% from ${entry.toLocaleString("en-US", { style: "currency", currency: "USD" })}`,
  }
}

const sentence = (text: string) => (/[.!?]$/.test(text) ? text : `${text}.`)

/** Why a sell naming a buy price has nothing to sell, from what came of the guru's buy at that price. */
export function namedBuyText(named: NamedBuy, source: SourceActivity): string | null {
  const price = Number(source.instructions[named.part]?.entry_price)
  if (!source.instructions[named.part] || !(price > 0)) return null
  const buy = price.toLocaleString("en-US", { style: "currency", currency: "USD" })
  if (!named.posted_at || !named.outcome) return sentence(`The guru's ${buy} buy never reached this account`)
  const day = monthDay(named.posted_at)
  if (named.outcome === "sold") return sentence(`The ${buy} buy on ${day} is already sold`)
  if (named.outcome === "not_filled") return sentence(`The ${buy} buy on ${day} never filled`)
  return `${sentence(`The ${buy} buy on ${day} wasn't made`)} ${sentence(reasonText(named.outcome))}`
}

/** The first held sell's reason across the post's accounts, or null when no sell is held for its buy price. */
export function namedBuySentence(source: SourceActivity): string | null {
  for (const destination of source.destinations as Destination[]) {
    const named = destination.named_buys?.[0]
    const text = named && namedBuyText(named, source)
    if (text) return text
  }
  return null
}
