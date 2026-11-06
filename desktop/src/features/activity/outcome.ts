import type { DestinationActivity, OrderActivity, SourceActivity } from "../../../shared/contract"
import { decText, parseDec } from "@/features/account/decimal"
import { money } from "@/lib/format"
import { dollars, partOfText, sharesOf } from "@/lib/quantity"
import { reasonText, sentence } from "@/lib/reasons"
import { deadlineText, endOfTradingDay, tradingDay } from "./deadline"
import { duration, filledAmount, num, orderDollars, plannedAmount } from "./amounts"
import { decisionTitle, enteredByOwner, stopPhrase } from "./reading"

// What each account did with a post, in plain words (DestinationOutcome.swift, ActivityCardOutcome.swift).

export type Tone = "positive" | "caution" | "critical" | "neutral" | "inactive"

/** The Badge variant for a tone. */
export const BADGE = {
  positive: "success-light",
  caution: "warning-light",
  critical: "destructive-light",
  neutral: "info-light",
  inactive: "outline",
} as const satisfies Record<Tone, string>

export type OrderKind = "filled" | "partly" | "working" | "stop" | "cancelled" | "failed" | "review"

export interface OrderOutcome {
  kind: OrderKind
  title: string
  detail: string
  tone: Tone
}

/** A lot the owner later sold by hand is theirs, not the post's. */
export const isOwnerSale = (o: OrderActivity) => o.client_id.startsWith("lotsale-")
export const isOwnerEntry = (o: OrderActivity) => o.client_id.startsWith("manual-")

const ENDED_UNFILLED = ["canceled", "expired", "done_for_day", "replaced", "released_unsubmitted", "aborted_before_submit"]

/**
 * A stop order that ended without selling anything: the engine cancels it to make room for a copied sell, shrinks it,
 * and places it again each session, because Alpaca keeps a stop for one day. It is the same stop, not a failure.
 */
const isSupersededStop = (o: OrderActivity) => o.order_type === "stop" && ENDED_UNFILLED.includes(o.status) && (num(o.filled_quantity) ?? 0) === 0

/** The orders of one account's post that the post's card tells about. */
export const shownOrders = (d: DestinationActivity): OrderActivity[] => (d.orders ?? []).filter((o) => !isSupersededStop(o))

/** Every part of a post an account decided: its buys and sells, then its stops. */
export const partOutcomes = (d: DestinationActivity): string[] => [...d.instruction_outcomes, ...(d.stop_outcomes ?? [])]

/** A stop order: resting at Alpaca counts as traded, and its fill is a sale. */
function stopOrderOutcome(order: OrderActivity): OrderOutcome {
  const as = (kind: OrderKind, title: string, tone: Tone, detail: string): OrderOutcome => ({ kind, title, tone, detail })
  // The post names its stop the same way whatever became of it: "Stop TQQQ at $50.95", then the state.
  const phrase = stopPhrase(order.symbol, num(order.stop_price) === null ? null : order.stop_price!)
  if (order.status === "filled") return as("filled", "Filled", "positive", `${phrase} filled`)
  if (order.status === "partially_filled" || (num(order.filled_quantity) ?? 0) > 0) return as("partly", "Partly filled", "neutral", `${phrase} partly filled`)
  if (order.status === "rejected") return as("failed", "Failed", "critical", `Alpaca rejected the stop for ${order.symbol}`)
  if (order.status === "uncertain" || order.status === "unrecognized") return as("review", "Needs review", "caution", `The broker has not confirmed the stop for ${order.symbol}`)
  return as("stop", "Stop placed", "positive", phrase)
}

/** One order in a phrase, dollar first: "Bought $199.82 of PM stock", "Order for $200 of PM stock was cancelled". */
export function orderOutcome(order: OrderActivity, count = 1): OrderOutcome {
  if (order.order_type === "stop") return stopOrderOutcome(order)
  const selling = order.side === "sell"
  const filled = num(order.filled_quantity) ?? 0
  const planned = plannedAmount(order) ?? order.symbol
  const done = filledAmount(order) ?? planned
  const as = (kind: OrderKind, title: string, tone: Tone, detail: string): OrderOutcome => ({ kind, title, tone, detail })
  if (order.status === "filled") {
    const base = isOwnerEntry(order) ? (selling ? "You sold" : "You bought") : selling ? "Sold" : "Bought"
    return as("filled", "Filled", "positive", count > 1 ? `${base} ${done} and ${count - 1} more` : `${base} ${done}`)
  }
  if (order.status === "partially_filled") {
    return as("partly", "Partly filled", "neutral", `Partly ${selling ? "sold" : "bought"}: ${done} so far`)
  }
  if (ENDED_UNFILLED.includes(order.status)) {
    if (filled > 0) return as("partly", "Partly filled", "neutral", `${selling ? "Sold" : "Bought"} ${done}, rest cancelled`)
    return as("cancelled", "Cancelled", "inactive", `Order for ${planned} was cancelled`)
  }
  if (order.status === "rejected") return as("failed", "Failed", "critical", `The broker rejected the order for ${order.symbol}`)
  if (order.status === "uncertain" || order.status === "unrecognized") {
    return as("review", "Needs review", "caution", `The broker has not confirmed the order for ${order.symbol}`)
  }
  const limit = num(order.limit_price)
  const working = `${selling ? "Selling" : "Buying"} ${planned}`
  return as("working", "Working", "neutral", limit === null ? working : `${working} at up to ${money(limit)}`)
}

export interface DestinationOutcome {
  title: string
  detail: string
  tone: Tone
}

/** What one account did with one post, in the order a trader cares about. */
export function destinationOutcome(d: DestinationActivity): DestinationOutcome {
  const copied = shownOrders(d).filter((o) => !isOwnerSale(o))
  if (copied[0]) return orderOutcome(copied[0], copied.length)
  if (d.status === "review_required") {
    const why = d.instruction_outcomes.find((o) => o !== "review_required" && o !== "pending")
    return { title: "Needs review", detail: reasonText(why ?? d.status), tone: "caution" }
  }
  if (["stale", "out_of_order", "ignored"].includes(d.status)) return { title: "Skipped", detail: reasonText(d.status), tone: "inactive" }
  if (d.status === "done") return { title: "Processed", detail: "Processing finished without an order.", tone: "neutral" }
  return { title: "Waiting", detail: "Waiting to be sized and sent", tone: "neutral" }
}

// ── A call held for the owner ──

/** Skips that hold a call back for the owner rather than refuse it (the engine's HELD_FOR_OWNER). */
export const HELD_FOR_OWNER = new Set(["approval_required", "named_buy_not_held"])
/** Outcomes that are not a skip: an order went out, the part is still working, or the owner approved it. */
export const CARRIED_ON = new Set(["order_linked", "pending", "waiting_for_quote", "approved_by_owner"])

const WAITING_REASONS: Record<string, string> = {
  repeats_an_earlier_call: "repeats an earlier call",
  conditional: "the trade has a condition",
  suggestion: "a suggestion, not a trade",
  unclear: "the post is unclear",
  price_range: "the guru gave a price range",
  price_at_market: "a buy at the market price",
  price_not_given: "no price given",
  named_buy_not_held: "no buy at the guru's price",
  sell_share_not_given: "the sell gives no size",
  batch_size_not_given: "no batch size given",
}

const holds = (d: DestinationActivity) => d.status === "review_required" || d.instruction_outcomes.some((o) => HELD_FOR_OWNER.has(o))

/** The accounts holding a call of this post for the owner, or none. */
export const waitingAccounts = (post: SourceActivity): string[] => post.destinations.filter(holds).map((d) => d.account_id)

/** Whether the owner can still copy it: held, its trading day not over, and not entered by hand. */
export const isOpenCall = (post: SourceActivity, now: Date) =>
  waitingAccounts(post).length > 0 && tradingDay(new Date(post.source_at)) === tradingDay(now) && !enteredByOwner(post)

// ── The card ──

export interface Fact {
  label: string
  value: string
}

/** One thing the account did with the post: usually one order, or why there was none. */
export interface Result {
  /** How it ended, for its mark: an order's own outcome; otherwise waiting on the owner, or a call not carried out. */
  tone: Tone
  headline: string
  facts: Fact[]
  note?: string
}

export interface AccountOutcome {
  id: string
  environment: string
  results: Result[]
  waits: boolean
}

export interface CardOutcome {
  title: string
  tone: Tone
  accounts: AccountOutcome[]
}

/** A buy the maximum per order cut below what its call asked for. */
export function wasTrimmed(order: OrderActivity): boolean {
  const [asked, allowed] = [num(order.requested_usd), num(order.budget_usd)]
  return asked !== null && allowed !== null && allowed < asked
}

const CUT_BY: Record<string, string> = {
  symbol_exposure_cap: "the room left under your limit for the stock",
  total_exposure_cap: "the room left under your total limit",
}

function cancelReason(order: OrderActivity): string {
  const buying = order.side !== "sell"
  switch (order.cancel_reason) {
    case "timeout": {
      const [limit, market] = [num(order.limit_price), num(buying ? order.quote_ask : order.quote_bid)]
      if (limit === null || market === null) return "not filled in time"
      if (buying && market > limit) return "the price ran above your limit"
      if (!buying && market < limit) return "the price fell below your limit"
      return "not filled in time"
    }
    case "replaced_by_sell": return "the guru sold it first"
    case "copying_stopped": return "copying stopped"
    case "stop_resized": return "the stop was resized after a sell"
    case "made_room_for_sell": return "the stop made room for a sell"
    case "cancelled_at_broker": return "cancelled at Alpaca"
    case "rejected": return "Alpaca rejected it"
    default: return order.status === "expired" ? "the trading day ended" : "cancelled before it filled"
  }
}

/** A sell placed this long after its post was read late, so the card says so. */
const LATE_SELL_SECONDS = 600

function orderResult(order: OrderActivity, postedAt: number): Result {
  const buying = order.side !== "sell"
  const outcome = orderOutcome(order)
  const limit = num(order.limit_price) === null ? null : money(order.limit_price)
  const facts: Fact[] = []
  const placed = Date.parse(order.created_at)
  const note =
    !buying && placed - postedAt >= LATE_SELL_SECONDS * 1000
      ? `Read ${duration((placed - postedAt) / 1000)} after the guru posted it. A sell is always copied, at no less than your lowest price.`
      : undefined
  const planned = plannedAmount(order) ?? order.symbol
  let headline: string
  switch (outcome.kind) {
    case "stop":
      headline = outcome.detail
      facts.push({ label: "Stop price", value: money(order.stop_price) })
      facts.push({ label: "Shares", value: sharesOf(parseDec(order.quantity) ?? 0n, order.symbol) })
      break
    case "filled":
      headline = order.order_type === "stop" ? outcome.detail : `${isOwnerSale(order) || (isOwnerEntry(order) && !buying) ? "You sold" : isOwnerEntry(order) ? "You bought" : buying ? "Bought" : "Sold"} ${filledAmount(order) ?? planned}`
      facts.push({ label: "Price", value: money(order.average_fill_price) })
      facts.push({ label: "Shares", value: sharesOf(parseDec(order.filled_quantity) ?? 0n, order.symbol) })
      break
    case "partly":
      headline = order.status === "partially_filled" ? `Partly filled: ${filledAmount(order) ?? planned} so far` : `Partly filled: ${filledAmount(order) ?? planned}, the rest cancelled`
      facts.push({ label: "Filled", value: partOfText(parseDec(order.filled_quantity) ?? 0n, parseDec(order.quantity) ?? 0n, order.symbol) })
      facts.push({ label: "Price", value: money(order.average_fill_price) })
      break
    case "working":
      headline = `${buying ? "Buying" : "Selling"} ${planned}`
      if (limit) facts.push({ label: buying ? "Your limit" : "Lowest sell price", value: limit })
      break
    case "failed":
      headline = buying ? "Not bought: Alpaca rejected it" : "Not sold: Alpaca rejected it"
      break
    case "review":
      headline = "Waiting for Alpaca to confirm"
      break
    default: {
      const market = num(buying ? order.quote_ask : order.quote_bid) === null ? null : money(buying ? order.quote_ask : order.quote_bid)
      headline =
        !buying && (order.status === "expired" || order.cancel_reason === "expired") && limit
          ? `Not sold by the close: the market stayed under your lowest price ${limit}`
          : `${buying ? "Not bought" : "Not sold"}: ${cancelReason(order)}`
      if (limit) facts.push({ label: buying ? "Your limit" : "Lowest sell price", value: limit })
      if (market) facts.push({ label: "Market", value: market })
      const [start, end] = [Date.parse(order.submitted_at ?? order.created_at), Date.parse(order.ended_at ?? "")]
      if (order.cancel_reason === "timeout" && Number.isFinite(start) && Number.isFinite(end)) {
        facts.push({ label: "Waited", value: duration((end - start) / 1000) })
      }
    }
  }
  const budget = num(order.budget_usd)
  if (budget !== null) {
    if (wasTrimmed(order)) {
      facts.push({ label: "Order", value: `${dollars(order.budget_usd)}, cut to ${CUT_BY[order.limited_by ?? ""] ?? "your largest single buy"}` })
      facts.push({ label: "The call asked for", value: dollars(order.requested_usd) })
    } else facts.push({ label: "Order", value: orderDollars(budget) })
  }
  return { tone: outcome.tone, headline, facts: facts.slice(0, 4), note }
}

function limitResult(post: SourceActivity, hit: NonNullable<DestinationActivity["limits_hit"]>[number]): Result {
  const symbol = post.instructions[hit.part]?.symbol ?? ""
  const selling = post.instructions[hit.part] !== undefined && post.instructions[hit.part]!.action !== "buy"
  const full = hit.scope === "symbol" ? `${symbol} is at your limit for one stock` : "you're at your total limit"
  const [limit, current] = [parseDec(hit.limit) ?? 0n, parseDec(hit.current) ?? 0n]
  const room = limit > current ? limit - current : 0n
  return {
    tone: "inactive",
    headline: `${selling ? "Not sold" : "Not bought"}: ${full}`,
    facts: [
      { label: hit.scope === "symbol" ? `Holding ${symbol}` : "Holding in total", value: dollars(hit.current) },
      { label: "Limit", value: dollars(hit.limit) },
      { label: "Room left", value: dollars(decText(room)) },
    ],
    note: "Less than $1 is left, Alpaca's smallest order.",
  }
}

/** Why a sell naming a buy price has nothing to sell, from what came of the guru's buy at that price. */
function namedBuySentence(named: NonNullable<DestinationActivity["named_buys"]>[number], post: SourceActivity): string | null {
  const entry = num(post.instructions[named.part]?.entry_price)
  if (entry === null) return null
  const buy = money(entry)
  if (!named.posted_at || !named.outcome) return sentence(`The guru's ${buy} buy never reached this account`)
  const day = new Date(named.posted_at).toLocaleDateString("en-US", { month: "short", day: "numeric" })
  if (named.outcome === "sold") return sentence(`The ${buy} buy on ${day} is already sold`)
  if (named.outcome === "not_filled") return sentence(`The ${buy} buy on ${day} never filled`)
  return `${sentence(`The ${buy} buy on ${day} wasn't made`)} ${sentence(reasonText(named.outcome))}`
}

/** The first held sell's reason across the post's accounts, or null when no sell is held for its buy price. */
export function namedBuyNote(post: SourceActivity): string | null {
  for (const d of post.destinations) {
    const named = d.named_buys?.[0]
    const text = named && namedBuySentence(named, post)
    if (text) return text
  }
  return null
}

function waitingResult(d: DestinationActivity, post: SourceActivity, open: boolean, now: Date): Result {
  const code = post.decision === "review" ? post.parser_reason : d.instruction_outcomes.find((o) => HELD_FOR_OWNER.has(o))
  // An account that asked to approve every order is asked to approve, not to copy.
  const approving = d.instruction_outcomes.includes("approval_required") && post.decision !== "review"
  if (!open) {
    return {
      tone: "inactive",
      headline: approving ? "Not sent" : "Not copied",
      facts: [],
      note: approving ? "Too late to approve: its trading day is over." : "Too late to copy: its trading day is over.",
    }
  }
  const short = approving || !code ? undefined : WAITING_REASONS[code]
  const named = code === "named_buy_not_held" ? d.named_buys?.[0] : undefined
  return {
    tone: "caution",
    headline: approving ? "Waiting for your approval" : short ? `Waiting for you: ${short}` : "Waiting for you",
    facts: [{ label: approving ? "Approve by" : "Copy by", value: deadlineText(endOfTradingDay(post.source_at), now) }],
    note: (named && namedBuySentence(named, post)) || (short === undefined && code ? sentence(reasonText(code)) : undefined),
  }
}

function staleNote(post: SourceActivity): string {
  if (!post.captured_at) return reasonText("stale")
  const late = (Date.parse(post.captured_at) - Date.parse(post.source_at)) / 1000
  return `Read ${duration(late)} after it was posted: older than this account copies buys. A sell is always copied.`
}

function resultsFor(d: DestinationActivity, post: SourceActivity, waits: boolean, open: boolean, now: Date): Result[] {
  const postedAt = Date.parse(post.source_at)
  const results = shownOrders(d).map((o) => orderResult(o, postedAt))
  d.instruction_outcomes.forEach((outcome, part) => {
    if (CARRIED_ON.has(outcome) || HELD_FOR_OWNER.has(outcome) || (waits && outcome === "review_required")) return
    const instruction = post.instructions[part]
    const selling = instruction !== undefined && instruction.action !== "buy"
    const limit = d.limits_hit?.find((h) => h.part === part)
    const later = d.later_buys?.find((l) => l.part === part)
    if (limit) results.push(limitResult(post, limit))
    else if (later && instruction) {
      const style: Intl.DateTimeFormatOptions = { weekday: "short", hour: "numeric", minute: "2-digit" }
      results.push({
        tone: "inactive",
        headline: `Not sold: ${d.account_id}'s ${instruction.symbol} was bought after this sell was posted (${new Date(later.bought_at).toLocaleString("en-US", style)} vs ${new Date(post.source_at).toLocaleString("en-US", style)}).`,
        facts: [],
      })
    } else results.push({ tone: "inactive", headline: selling ? "Not sold" : "Not bought", facts: [], note: reasonText(outcome) })
  })
  // A stop the account did not place says why: mostly that it does not follow the guru's stops.
  const stopOutcomes = d.stop_outcomes ?? []
  stopOutcomes.forEach((outcome, part) => {
    if (CARRIED_ON.has(outcome) || HELD_FOR_OWNER.has(outcome)) return
    const stop = post.stops?.[part]
    results.push({ tone: "inactive", headline: stop ? `${stopPhrase(stop.symbol, stop.stop_price)} not placed` : "Stop not placed", facts: [], note: reasonText(outcome) })
  })
  // A sell with no fresh bid yet keeps waiting, and asks Alpaca again every 30 seconds.
  if (d.instruction_outcomes.includes("waiting_for_quote")) results.push({ tone: "neutral", headline: reasonText("waiting_for_quote"), facts: [] })
  if (waits) results.push(waitingResult(d, post, open, now))
  else if (["stale", "out_of_order"].includes(d.status) && results.length === 0) {
    results.push({ tone: "inactive", headline: "Not copied", facts: [], note: d.status === "stale" ? staleNote(post) : reasonText(d.status) })
  }
  if (results.length === 0) results.push({ tone: destinationOutcome(d).tone, headline: destinationOutcome(d).detail, facts: [] })
  return results
}

/** How a post ended: one title (Traded, Traded smaller, Waiting for you, Skipped, Ignored, …) and, per account, what it did. */
export function cardOutcome(post: SourceActivity, now: Date): CardOutcome {
  const held = waitingAccounts(post)
  const open = isOpenCall(post, now)
  const accounts = post.destinations.map((d) => {
    const waits = held.includes(d.account_id) && !(d.orders ?? []).some(isOwnerEntry)
    return { id: d.account_id, environment: d.environment ?? "paper", results: resultsFor(d, post, waits, open, now), waits: waits && open }
  })
  // The owner's own sales are theirs, not the post's: they never decide how the post did.
  const orders = post.destinations.flatMap(shownOrders).filter((o) => !isOwnerSale(o))
  const outcomes = orders.map((o) => orderOutcome(o))
  const unsettled = outcomes.find((o) => o.tone !== "positive")
  const skipped = post.destinations.some((d) => partOutcomes(d).some((o) => !CARRIED_ON.has(o)) || ["stale", "out_of_order"].includes(d.status))
  let title: string
  let tone: Tone
  if (post.decision === "ignore") [title, tone] = ["Ignored", "inactive"]
  else if (open) [title, tone] = ["Waiting for you", "caution"]
  else if (unsettled && outcomes.some((o) => o.tone === "positive")) [title, tone] = ["Partly traded", "neutral"]
  else if (unsettled) [title, tone] = [unsettled.title, unsettled.tone]
  else if (outcomes.length > 0) [title, tone] = orders.some(wasTrimmed) ? ["Traded smaller", "neutral"] : ["Traded", "positive"]
  else if (held.length > 0) [title, tone] = ["Expired", "inactive"]
  else if (skipped) [title, tone] = ["Skipped", "inactive"]
  else if (post.decision === "trade") [title, tone] = [decisionTitle(post), "positive"]
  else if (post.decision === "review") [title, tone] = [decisionTitle(post), "caution"]
  else [title, tone] = [decisionTitle(post), "neutral"]
  return { title, tone, accounts }
}

/** Fresh posts replace stale copies of the same post, and the list stays newest first. */
export function mergePosts(current: SourceActivity[], fresh: SourceActivity[]): SourceActivity[] {
  const bySequence = new Map(current.map((p) => [p.sequence, p]))
  let changed = false
  for (const post of fresh) {
    const had = bySequence.get(post.sequence)
    // A refresh that brings nothing new keeps the same array, so nothing on screen redraws.
    if (had && JSON.stringify(had) === JSON.stringify(post)) continue
    bySequence.set(post.sequence, post)
    changed = true
  }
  return changed ? [...bySequence.values()].sort((a, b) => b.sequence - a.sequence) : current
}
