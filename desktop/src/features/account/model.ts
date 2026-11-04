import type { AccountOverview, OrderActivity, SourceActivity } from "../../../shared/contract"
import { monthDay } from "@/lib/format"
import { decMul, decRound, decText, parseDec } from "./decimal"
import { dollars, usd } from "./quantity"
import { callPhrase, isWaiting } from "./waiting"

/** The badge tones the page uses for what became of a post. */
export type OutcomeTone = "success-light" | "warning-light" | "destructive-light" | "outline"

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

const call = (post: SourceActivity) => (post.instructions[0] ? callPhrase(post.instructions[0]) : "Trade call")

/** Orders that ended without filling, as the broker's states name them. */
const ENDED = new Set(["canceled", "expired", "done_for_day", "replaced", "released_unsubmitted", "aborted_before_submit"])

/** "$200 of PM": what the order was sized to spend, its budget or its shares at its limit. */
function planned(order: OrderActivity): string {
  const budget = parseDec(order.budget_usd)
  const quantity = parseDec(order.quantity)
  const limit = parseDec(order.limit_price)
  const usd = budget ?? (quantity !== null && limit !== null ? decMul(quantity, limit) : null)
  return usd === null ? order.symbol : `${dollars(decText(decRound(usd, 2)))} of ${order.symbol}`
}

/** "$199.82 of PM": what filled, or what was planned when the fill is not on record. */
function filled(order: OrderActivity): string {
  const quantity = parseDec(order.filled_quantity)
  const price = parseDec(order.average_fill_price)
  return quantity !== null && quantity > 0n && price !== null ? `${usd(decText(decMul(quantity, price)))} of ${order.symbol}` : planned(order)
}

/** What one order did, in the order a trader cares about (DestinationOutcome.swift): Copied only when it filled. */
export function orderOutcome(order: OrderActivity, count: number): PostOutcome {
  const selling = order.side === "sell"
  const done = filled(order)
  const some = (parseDec(order.filled_quantity) ?? 0n) > 0n
  if (order.status === "filled") {
    const text = `${order.client_id.startsWith("manual-") ? (selling ? "You sold" : "You bought") : selling ? "Sold" : "Bought"} ${done}`
    return { label: "Copied", tone: "success-light", read: count > 1 ? `${text} and ${count - 1} more` : text }
  }
  if (order.status === "partially_filled") {
    return { label: "Partly filled", tone: "warning-light", read: `${selling ? "Partly sold" : "Partly bought"}: ${done} so far` }
  }
  if (ENDED.has(order.status)) {
    return some
      ? { label: "Partly filled", tone: "warning-light", read: `${selling ? "Sold" : "Bought"} ${done}, rest cancelled` }
      : { label: "Cancelled", tone: "outline", read: `Order for ${planned(order)} was cancelled` }
  }
  if (order.status === "rejected") return { label: "Failed", tone: "destructive-light", read: `The broker rejected the order for ${order.symbol}` }
  if (order.status === "uncertain" || order.status === "unrecognized") {
    return { label: "Needs review", tone: "warning-light", read: `The broker has not confirmed the order for ${order.symbol}` }
  }
  const limit = order.limit_price ? ` at up to ${usd(order.limit_price)}` : ""
  return { label: "Working", tone: "outline", read: `${selling ? "Selling" : "Buying"} ${planned(order)}${limit}` }
}

/** What a guru post did for one account: chat, a suggestion waiting for the owner, or a trade call. */
export function postOutcome(post: SourceActivity, accountId: string, now: Date): PostOutcome {
  if (post.decision === "ignore") return { label: "Chat", tone: "outline", read: "Just chat" }
  if (isWaiting(post, now)) return { label: "Waits for you", tone: "warning-light", read: "Needs your review" }
  const read = call(post)
  const destination = post.destinations.find((d) => d.account_id === accountId)
  // What the post itself did; a lot the owner later sold by hand is theirs, not the post's.
  const orders = (destination?.orders ?? []).filter((o) => !o.client_id.startsWith("lotsale-"))
  if (orders[0]) return orderOutcome(orders[0], orders.length)
  const outcomes = destination?.instruction_outcomes ?? []
  if (outcomes.includes("order_linked")) return { label: "Order placed", tone: "outline", read }
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
