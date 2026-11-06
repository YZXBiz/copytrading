import type { SourceActivity, SourceInstruction } from "../../../shared/contract"
import { HELD_FOR_OWNER, isOpenCall, namedBuyNote, waitingWhy } from "@/features/activity/outcome"

// The call a post holds for the owner (WaitingCall.swift): what Copy places, and which answer it asks for. Whether a
// post still waits, and until when, is decided once, in the Activity feature (`isOpenCall`, `endOfTradingDay`), so the
// account page and the Activity screen can never disagree; the owner's own skip is the one thing only this page knows.

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

/** Why the call waits at this account, in Activity's words: the line, and the sentence under it when there is one. */
export function whyWaits(call: WaitingCall, accountId: string): { headline: string; note?: string } | null {
  const destination = call.source.destinations.find((d) => d.account_id === accountId)
  return destination ? waitingWhy(destination, call.source) : null
}

/** The call a post holds for the owner right now, or null: still open by Activity's rule, and not skipped here. */
export const openCall = (source: SourceActivity, { skipped, now }: { skipped: boolean; now: Date }): WaitingCall | null =>
  skipped || !isOpenCall(source, now) ? null : waitingCall(source)

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

/** What a waiting call asks for, in one line: its first call and how many more follow, or that the owner enters the trade. */
export const meaningOf = (call: WaitingCall): string =>
  call.calls[0] ? callPhrase(call.calls[0]) + (call.calls.length > 1 ? ` and ${call.calls.length - 1} more` : "") : "Enter the trade yourself"

/** The first call's gain against the buy it names. A sell held for its buy price has no buy to gain on, so it shows none. */
export const callGain = (call: WaitingCall): ReturnType<typeof gainLine> => (call.calls[0] && !namedBuyNote(call.source) ? gainLine(call.calls[0]) : null)

/** The button's word: enter the trade yourself, approve what the account held, or copy what the post called. */
export const copyLabel = (call: WaitingCall): string => (call.calls.length === 0 ? "Enter trade" : call.awaitsApproval ? "Approve" : "Copy")

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
