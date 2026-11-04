import type { LotSalePreview, LotSaleResult, ManualOrderPlan } from "../../../shared/contract"
import { DEC_ONE, decDown, decMul, decRound, decText, parseDec } from "./decimal"
import { isCoin, partOfText, sharesText, usd } from "@/lib/quantity"
import { codeWords, reasonText } from "@/lib/reasons"

// Selling shares from one lot (LotSaleFlow.swift, LotSaleSheet.swift): choose how much of it, review a fresh
// preview, confirm once. Every quantity is an exact decimal, so the engine never hears of 0.30000000000000004.

/** The parts of a lot to choose from. */
export const SALE_PARTS = [
  { title: "¼", part: "0.25" },
  { title: "½", part: "0.5" },
  { title: "¾", part: "0.75" },
  { title: "All", part: "1" },
] as const

/**
 * A part of the lot. Parts round down to hundredths of a share, or a coin to the billionth Alpaca keeps it in,
 * so a sale never asks for more than the lot holds.
 */
export function partAmount(remaining: bigint, part: bigint, symbol: string): bigint {
  return part >= DEC_ONE ? remaining : decDown(decMul(remaining, part), isCoin(symbol) ? 9 : 2)
}

/** The parts a lot can be split into; a part too small to sell is left out. */
export const saleChoices = (remaining: bigint, symbol: string) =>
  SALE_PARTS.map((p) => ({ title: p.title, amount: partAmount(remaining, parseDec(p.part)!, symbol) })).filter((c) => c.amount > 0n)

const upToFour = (value: bigint) => decText(decRound(value, 4))

/** The chosen part in words: "0.44 of 0.885 shares", or "All 0.885 shares" rather than the same number twice. */
export function sharesLine(shares: bigint, remaining: bigint, symbol: string): string {
  if (isCoin(symbol)) return shares === remaining ? `All ${sharesText(remaining, symbol)}` : partOfText(shares, remaining, symbol)
  return shares === remaining ? `All ${upToFour(remaining)} shares` : `${upToFour(shares)} of ${upToFour(remaining)} shares`
}

/** The button that checks the sale: "Sell 0.44 WMT…". */
export const reviewLabel = (shares: bigint, symbol: string) => `Sell ${isCoin(symbol) ? decText(decRound(shares, 9)) : upToFour(shares)} ${symbol}…`

/** What the sale will do, in a sentence: the limit order, and what it comes to at today's bid. */
export function saleSentence(plan: ManualOrderPlan, preview: LotSalePreview): string {
  const quantity = parseDec(plan.qty) ?? 0n
  const noun = quantity === DEC_ONE ? "share" : "shares"
  const shares = isCoin(plan.symbol) ? sharesText(quantity, plan.symbol) : `${decText(quantity)} ${noun} of ${plan.symbol}`
  const limit = plan.limit_price
  if (!limit) return shares
  const sentence = `Sells ${shares} with a limit order at ${usd(limit)}. It fills at that price or better, or not at all.`
  const bid = parseDec(preview.fresh_price)
  return bid === null ? sentence : `${sentence} At today's bid of ${usd(preview.fresh_price)}, that comes to about ${usd(decText(decMul(quantity, bid)))}.`
}

export type SaleTone = "success" | "neutral" | "warning" | "destructive"

/** What became of a confirmed sale, in a title, a line on what happens next, and a tone. */
export function saleOutcome(result: LotSaleResult, symbol: string): { title: string; detail: string; tone: SaleTone } {
  const filled = parseDec(result.filled_qty) ?? 0n
  const price = result.filled_avg_price ? ` at ${usd(result.filled_avg_price)}` : ""
  switch (result.status) {
    case "filled":
      return {
        title: isCoin(symbol) ? `Sold ${sharesText(filled, symbol)}${price}` : `Sold ${decText(filled)} ${symbol}${price}`,
        detail: "Those shares are out of this lot. Activity shows the sale beside the post that bought them.",
        tone: "success",
      }
    case "partially_filled":
      return {
        title: `Sold ${sharesText(filled, symbol)} so far`,
        detail: "The broker has the order. Accounts updates as it fills.",
        tone: "neutral",
      }
    case "accepted":
    case "prepared":
      return { title: "Your sale is in", detail: "The broker has the order. Accounts updates as it fills.", tone: "neutral" }
    case "uncertain":
      return {
        title: "Waiting to hear from the broker",
        detail: "CopyTrading did not get the broker's answer. It checks again on its own and never sends the order twice.",
        tone: "warning",
      }
    case "rejected":
      return { title: "Nothing was sent", detail: reasonText(result.reason), tone: "destructive" }
    default:
      return { title: codeWords(result.status), detail: reasonText(result.reason ?? result.status), tone: "destructive" }
  }
}
