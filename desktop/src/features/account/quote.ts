import type { AccountOverview, MarketQuote } from "../../../shared/contract"
import { timeOfDay, dateTime } from "@/lib/format"
import { parseDec } from "./decimal"
import { usd } from "@/lib/quantity"

// A stock's latest quote from the account's broker, asked for as the trade sheet opens and as the owner types a
// ticker (LiveQuote.swift): a buy pays the ask, a sell gets the bid. The price says when it was quoted, and a quote
// too old to be the market now says so.

/** Symbols the engine can quote: a stock's ticker (a letter, then letters, digits or a dot), or a coin's dollar pair. */
export const canQuote = (symbol: string) => /^[A-Z][A-Z0-9.]{0,9}$/.test(symbol) || /^[A-Z]{2,10}\/USD$/.test(symbol)

/** How long a quote stands for the market, in seconds. The engine's preview reads its own, fresher, before anything is placed. */
const LIVE_FOR = 120

const positive = (text: string | null | undefined) => {
  const value = parseDec(text)
  return value !== null && value > 0n ? (text as string) : null
}

/** What a buy pays or a sell gets, from the other side when the book has only one. */
export function quotePrice(quote: MarketQuote | null, isSell: boolean): string | null {
  const bid = positive(quote?.bid)
  const ask = positive(quote?.ask)
  return isSell ? (bid ?? ask) : (ask ?? bid)
}

/** Quoted within the last two minutes; a quote with no time is never live. */
export function isLive(quote: MarketQuote | null, now: Date): boolean {
  if (!quote?.timestamp) return false
  const age = (now.getTime() - new Date(quote.timestamp).getTime()) / 1000
  return age > -5 && age <= LIVE_FOR
}

/** The price only while the quote is live: the market a buy at the market pays. */
export const livePrice = (quote: MarketQuote | null, isSell: boolean, now: Date) => (isLive(quote, now) ? quotePrice(quote, isSell) : null)

/** When it was quoted: "8:19 AM" today, "Oct 14, 7:19 PM" before. */
const when = (iso: string, now: Date) => (new Date(iso).toDateString() === now.toDateString() ? timeOfDay(iso) : dateTime(iso))

/** "≈ $226.56 · 11:53 AM" beside Market while the quote is live; null otherwise. */
export function quoteDetail(quote: MarketQuote | null, isSell: boolean, now: Date): string | null {
  const price = livePrice(quote, isSell, now)
  return price && quote?.timestamp ? `≈ ${usd(price)} · ${when(quote.timestamp, now)}` : null
}

/** Why there is no market price, said plainly. Null while the quote is live. */
export function quoteProblem(symbol: string, quote: MarketQuote | null, isSell: boolean, now: Date): string | null {
  if (quotePrice(quote, isSell) === null) return `No quote for ${symbol}`
  if (isLive(quote, now)) return null
  return quote?.timestamp ? `No live quote for ${symbol} since ${when(quote.timestamp, now)}` : `No live quote for ${symbol}`
}

/** A stock CopyTrading bought and still holds in the chosen accounts: what a hand-entered sell can pick from. */
export interface Holding {
  symbol: string
  /** CopyTrading's shares across the chosen accounts. */
  shares: bigint
  /** The broker's last price; null when the broker was not read. */
  price: string | null
}

/** The stocks held in `accountIds` (every account when none is chosen), largest first. Shares held outside CopyTrading are never sold by it, so they are left out. */
export function holdings(accounts: AccountOverview[], accountIds: ReadonlySet<string>): Holding[] {
  const chosen = accountIds.size === 0 ? accounts : accounts.filter((a) => accountIds.has(a.account_id))
  const bySymbol = new Map<string, Holding>()
  for (const position of chosen.flatMap((a) => a.positions)) {
    const owned = parseDec(position.owned_qty)
    if (owned === null || owned <= 0n) continue
    const symbol = position.symbol.toUpperCase()
    const existing = bySymbol.get(symbol)
    bySymbol.set(symbol, { symbol, shares: (existing?.shares ?? 0n) + owned, price: existing?.price ?? position.current_price })
  }
  const value = (h: Holding) => (h.price === null ? 0n : (parseDec(h.price) ?? 0n) * h.shares)
  return [...bySymbol.values()].sort((a, b) => (value(a) === value(b) ? a.symbol.localeCompare(b.symbol) : value(a) > value(b) ? -1 : 1))
}
