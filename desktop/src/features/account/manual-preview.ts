import type { ManualCommandResult, ManualOrderPreview } from "../../../shared/contract"
import { parseDec } from "./decimal"
import { dollars, shareCount, sharesText, usd } from "@/lib/quantity"
import { refusalLine, refusalOutcome, refusalReason, reasonText } from "@/lib/reasons"

// What the engine says one drafted trade would place in one account (ManualPreviewResult.swift): the order, or
// why it cannot go, then what became of it once sent.

/** Ready to send: the engine planned an order and found nothing in the way. */
export const isReady = (preview: ManualOrderPreview | null) => preview !== null && preview.plan !== null && preview.reasons.length === 0

/** The order in the words the owner confirms: a buy by the dollars it spends, a sell by its shares. */
export function previewHeadline(preview: ManualOrderPreview | null, accountId: string, index: number): string {
  const plan = preview?.plan
  if (!plan) {
    const instruction = preview?.instruction
    return instruction ? `${instruction.action === "buy" ? "Buy" : "Sell"} ${instruction.symbol} in ${accountId}` : `${accountId}, trade ${index + 1}`
  }
  if (plan.budget_usd !== null) return `Buy ${dollars(plan.budget_usd)} of ${plan.symbol} in ${accountId}`
  const quantity = parseDec(plan.qty)
  const shares = quantity === null ? plan.qty : shareCount(quantity, plan.symbol)
  const limit = plan.limit_price ? ` at ${usd(plan.limit_price)}` : ""
  return `${plan.side.toLowerCase() === "sell" ? "Sell" : "Buy"} ${shares} ${plan.symbol}${limit} in ${accountId}`
}

/** "2 min", "3 h": how old the post was, to one unit. */
function age(seconds: number): string {
  if (seconds < 60) return `${Math.floor(seconds)} s`
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min`
  return `${Math.floor(seconds / 3600)} h`
}

/** A buy's shares at its limit, then the fresh price and the post's age, shown whether or not the order can go: one fact each. */
export function previewDetail(preview: ManualOrderPreview): string[] {
  const parts: string[] = []
  const { plan } = preview
  const quantity = parseDec(plan?.qty)
  if (plan && plan.budget_usd !== null && quantity !== null && plan.limit_price) {
    parts.push(`${sharesText(quantity, plan.symbol)} at ${usd(plan.limit_price)} or less`)
  }
  if (preview.fresh_price) parts.push(`${preview.instruction.action === "buy" ? "Ask" : "Bid"} ${usd(preview.fresh_price)}`)
  parts.push(`posted ${age(preview.source_age_seconds)} ago`)
  return parts
}

/** Why the order cannot go, each reason once, in the by-hand flow's words. */
export function previewProblems(preview: ManualOrderPreview): string[] {
  const reasons = preview.reasons.map(refusalReason)
  const blocked = preview.checks.filter((c) => c.status === "blocked" && !(c.reason && preview.reasons.includes(c.reason))).map((c) => refusalReason(c.reason ?? c.name))
  return [...new Set([...reasons, ...blocked])]
}

/** What the owner should know before sending, without stopping them: an ask above the buy's limit, with the numbers. */
export function previewWarnings(preview: ManualOrderPreview): string[] {
  return preview.checks.filter((c) => c.status === "warning" && c.reason === "quote_above_limit").map(() => aboveLimit(preview))
}

function aboveLimit(preview: ManualOrderPreview): string {
  const ask = parseDec(preview.fresh_price)
  const limit = parseDec(preview.limit_price)
  const price = parseDec(preview.instruction.price)
  if (ask === null || limit === null || price === null || price === 0n) return reasonText("quote_above_limit")
  // Hundredths of a percent, rounded half up, in exact arithmetic.
  const allowance = Number(((limit - price) * 20000n + price) / (2n * price)) / 100
  const quote = preview.quote?.bid ? `The ask is ${usd(preview.fresh_price)} (bid ${usd(preview.quote.bid)})` : `The ask is ${usd(preview.fresh_price)}`
  return `${quote}, above your limit of ${usd(preview.limit_price)}: ${usd(preview.instruction.price)} plus your ${allowance}%. It may not fill, and is cancelled if it hasn't in time.`
}

export type Status = { text: string; tone: "success-light" | "destructive-light" | "warning-light" | "outline" }

/** "Ready", "Can't send", or what became of the order after it was sent. */
export function previewStatus(preview: ManualOrderPreview | null, outcome: Outcome | undefined, failed: boolean): Status | null {
  if (outcome) {
    const code = outcome.result?.status ?? (outcome.error ? "failed" : "pending")
    const tone = ["filled", "partially_filled", "accepted", "prepared"].includes(code) ? "success-light" : ["uncertain", "pending"].includes(code) ? "warning-light" : "destructive-light"
    return { text: code === "failed" ? "Failed" : code.charAt(0).toUpperCase() + code.slice(1).replace(/_/g, " "), tone }
  }
  if (!preview) return failed ? null : { text: "Checking", tone: "outline" }
  return isReady(preview) ? { text: "Ready", tone: "success-light" } : { text: "Can't send", tone: "destructive-light" }
}

/** What the engine said to a confirmed order. */
export interface Outcome {
  result: ManualCommandResult | null
  error: string | null
}

/** Why a confirmed order did not go well: the engine's reason, worded, plus any error from placing it. */
export function outcomeProblems(outcome: Outcome | undefined): string[] {
  if (!outcome) return []
  const lines: string[] = []
  if (outcome.error) lines.push(refusalLine(outcome.error))
  if (outcome.result) {
    const line = refusalOutcome(outcome.result)
    if (line) lines.push(line)
  }
  return [...new Set(lines)]
}

/** An order may have gone: a refusal, or an order the broker turned down, leaves the call open to review again. */
export const hasSent = (outcomes: Outcome[]) =>
  outcomes.some((o) => (o.result ? !["rejected", "broker_rejected"].includes(o.result.status) : o.error === "confirm_failed"))
