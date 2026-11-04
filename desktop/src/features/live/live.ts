import type { AccountOverview, MarketQuote } from "../../../shared/contract"
import { isLive } from "@/features/account/quote"
import { parseDec } from "@/features/account/decimal"

type Position = AccountOverview["positions"][number]

/** How often held symbols are asked for again while the window is visible. */
export const TICK_MS = 5_000

/** A quote's mark: the middle of bid and ask, or the one side there is; null unless the quote is live. */
export function markPrice(quote: MarketQuote | null, now: Date): number | null {
  if (!isLive(quote, now)) return null
  const sides = [quote?.bid, quote?.ask].map((text) => (parseDec(text) !== null ? Number(text) : 0)).filter((n) => n > 0)
  return sides.length === 0 ? null : sides.reduce((a, b) => a + b, 0) / sides.length
}

/** Which way a price moved; null when it did not, or when there is nothing to compare. */
export function tickDirection(before: number | null | undefined, after: number | null | undefined): "up" | "down" | null {
  if (before == null || after == null || before === after) return null
  return after > before ? "up" : "down"
}

export interface LiveRow {
  price: number | null
  value: number | null
  gain: number | null
  /** Gain as a fraction of what the shares cost. */
  gainFraction: number | null
}

/**
 * The row's price, value and gain at the live price. The broker's own figures are the base, so the cost basis and
 * share count it uses stay its own; the live price only moves the value, and the gain by the same amount.
 */
export function liveRow(position: Position, live: number | null): LiveRow {
  const price = live ?? numberOrNull(position.current_price)
  const value = numberOrNull(position.market_value)
  const gain = numberOrNull(position.unrealized_pl)
  const last = numberOrNull(position.current_price)
  if (live === null || last === null || last <= 0 || value === null) return { price, value, gain, gainFraction: numberOrNull(position.unrealized_plpc) }
  const moved = (value * live) / last
  const cost = gain === null ? null : value - gain
  const liveGain = gain === null ? null : gain + (moved - value)
  return { price, value: moved, gain: liveGain, gainFraction: liveGain !== null && cost !== null && cost > 0 ? liveGain / cost : numberOrNull(position.unrealized_plpc) }
}

const numberOrNull = (text: string | null | undefined) => (parseDec(text) === null ? null : Number(text))
