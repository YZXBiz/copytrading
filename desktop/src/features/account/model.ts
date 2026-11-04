import type { AccountOverview, SourceActivity } from "../../../shared/contract"
import { monthDay } from "@/lib/format"

/** The badge tones the page uses for what became of a post. */
export type OutcomeTone = "success-light" | "warning-light" | "outline"

export interface PostOutcome {
  label: string
  tone: OutcomeTone
  /** One line on what the post meant for this account. */
  read: string
}

const SKIP_REASONS: Record<string, (symbol: string) => string> = {
  no_open_lot: (symbol) => `No ${symbol} bought for this guru`,
  named_buy_not_held: () => "The buy it named is not held",
  bought_after_sell: () => "The buy came after this sale",
  approval_required: () => "Needs your approval",
}

/** "no_open_lot" becomes "No open lot": a code the page has no sentence for still reads as words. */
function words(code: string): string {
  const text = code.replace(/_/g, " ")
  return text.charAt(0).toUpperCase() + text.slice(1)
}

function call(post: SourceActivity): string {
  const first = post.instructions[0]
  if (!first) return "Trade call"
  const verb = first.action === "buy" ? "Buy" : first.action === "close" ? "Sell all" : "Trim"
  return `${verb} ${first.symbol}${first.price ? ` at $${Number(first.price).toFixed(2)}` : ""}`
}

/** What a guru post did for one account: chat, a suggestion waiting for the owner, or a trade call. */
export function postOutcome(post: SourceActivity, accountId: string, now: Date): PostOutcome {
  if (post.decision === "ignore") return { label: "Chat", tone: "outline", read: "Just chat" }
  if (isWaiting(post, now)) return { label: "Waits for you", tone: "warning-light", read: "Needs your review" }
  const read = call(post)
  const outcomes = post.destinations.find((d) => d.account_id === accountId)?.instruction_outcomes ?? []
  if (outcomes.includes("order_linked")) return { label: "Copied", tone: "success-light", read }
  if (outcomes.length === 0 && post.decision === "review") {
    return { label: "Not copied", tone: "outline", read: "Its trading day ended before you decided" }
  }
  if (outcomes.every((o) => o === "pending" || o === "waiting_for_quote")) {
    return { label: "Working", tone: "outline", read }
  }
  const code = outcomes.find((o) => o !== "pending" && o !== "waiting_for_quote") ?? ""
  const symbol = post.instructions[0]?.symbol ?? ""
  return { label: "Skipped", tone: "outline", read: `${read} · ${SKIP_REASONS[code]?.(symbol) ?? words(code)}` }
}

/** Skips that hold a call for the owner rather than refuse it (the engine's HELD_FOR_OWNER). */
const HELD_FOR_OWNER = new Set(["approval_required", "named_buy_not_held"])

/** The New York trading day an instant belongs to; from 20:00 it is the next day's (WaitingCall.swift). */
export function tradingDay(instant: Date): string {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone: "America/New_York",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      hourCycle: "h23",
    })
      .formatToParts(instant)
      .map((part) => [part.type, Number(part.value)]),
  ) as Record<"year" | "month" | "day" | "hour", number>
  const day = new Date(Date.UTC(parts.year, parts.month - 1, parts.day + (parts.hour >= 20 ? 1 : 0)))
  return day.toISOString().slice(0, 10)
}

/**
 * A post waits for the owner while an account holds its call (a review, an approval, a sell naming
 * a buy that is not held) and its trading day is not over, as WaitingCall.swift decides. The
 * owner's own skips and hand-entered trades live in the app, not the engine, so they are not seen.
 */
export function isWaiting(post: SourceActivity, now: Date): boolean {
  const held = post.destinations.some(
    (d) => d.status === "review_required" || d.instruction_outcomes.some((o) => HELD_FOR_OWNER.has(o)),
  )
  return held && tradingDay(new Date(post.source_at)) === tradingDay(now)
}

/** Positions worth a row: the broker keeps fractions of a cent after a sale. */
export const heldPositions = (account: AccountOverview) =>
  account.positions.filter((p) => Number(p.market_value ?? 0) >= 0.01)

/** "赵哥 · bought Oct 22": which guru's post opened the holding, and when. */
export function holdingNote(position: AccountOverview["positions"][number]): string | null {
  const lot = position.lots[0]
  if (!lot?.guru_id) return null
  return lot.posted_at ? `${lot.guru_id} · bought ${monthDay(lot.posted_at)}` : lot.guru_id
}

/** Day change as a fraction of yesterday's close. */
export function dayChange(account: AccountOverview): { amount: number; fraction: number } | null {
  const b = account.balance
  if (!b) return null
  const amount = Number(b.day_change_usd)
  const close = Number(b.previous_close_equity)
  return { amount, fraction: close > 0 ? amount / close : 0 }
}
