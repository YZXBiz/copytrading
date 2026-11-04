import type { AccountOverview, SourceActivity } from "../../../shared/contract"
import { monthDay } from "@/lib/format"
import { BADGE, isOpenCall, isOwnerSale, orderOutcome } from "@/features/activity/outcome"
import { callPhrase } from "./waiting"

/** The badge tones the page uses for what became of a post: Activity's, so a post reads the same on both screens. */
export type OutcomeTone = (typeof BADGE)[keyof typeof BADGE]

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

/** What a guru post did for one account: chat, a suggestion waiting for the owner, or a trade call. */
export function postOutcome(post: SourceActivity, accountId: string, now: Date): PostOutcome {
  if (post.decision === "ignore") return { label: "Chat", tone: BADGE.inactive, read: "Just chat" }
  if (isOpenCall(post, now)) return { label: "Waits for you", tone: BADGE.caution, read: "Needs your review" }
  const read = call(post)
  const destination = post.destinations.find((d) => d.account_id === accountId)
  // What the post itself did, said as Activity says it (Copied only once an order filled); a lot the owner later
  // sold by hand is theirs, not the post's.
  const orders = (destination?.orders ?? []).filter((o) => !isOwnerSale(o))
  if (orders[0]) {
    const outcome = orderOutcome(orders[0], orders.length)
    return { label: outcome.kind === "filled" ? "Copied" : outcome.title, tone: BADGE[outcome.tone], read: outcome.detail }
  }
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
