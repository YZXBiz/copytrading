import { money } from "@/lib/format"
import { DEC_ONE, decRound, decText, parseDec } from "./decimal"

// How much of a stock or coin, and what it costs, as Humanize.swift words them.

/** A coin's pair ("BTC/USD") rather than a stock: no stock has a slash. */
export const isCoin = (symbol: string) => symbol.includes("/")
const coinOf = (symbol: string) => symbol.split("/")[0]!

/** Groups thousands of a plain decimal string without touching its digits. */
function grouped(text: string): string {
  const [whole, fraction] = text.split(".")
  const sign = whole!.startsWith("-") ? "-" : ""
  const digits = whole!.replace("-", "").replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  return `${sign}${digits}${fraction ? `.${fraction}` : ""}`
}

const isOne = (value: bigint) => decRound(value, 2) === DEC_ONE

/**
 * The count alone: a stock's is whole when within a hundredth of a whole number, else to three decimals,
 * with "≈" when rounded; a coin's is to the billionth Alpaca keeps it in.
 */
export function shareCount(value: bigint, symbol: string): string {
  if (isCoin(symbol)) return grouped(decText(decRound(value, 9)))
  const whole = decRound(value, 0)
  const diff = value > whole ? value - whole : whole - value
  const shown = diff >= DEC_ONE / 100n ? decRound(value, 3) : whole
  return `${shown === value ? "" : "≈"}${grouped(decText(shown))}`
}

/** "2.985 shares", "1 share", "0.001231481 units of BTC". */
export function sharesText(value: bigint, symbol: string): string {
  if (isCoin(symbol)) return `${shareCount(value, symbol)} units of ${coinOf(symbol)}`
  return `${shareCount(value, symbol)} ${isOne(value) ? "share" : "shares"}`
}

/** What comes before "of SYMBOL": a stock's shares, or a coin's count alone (the pair already names it). */
export const sharesOf = (value: bigint, symbol: string) => (isCoin(symbol) ? shareCount(value, symbol) : sharesText(value, symbol))

/** "0.44 of 0.885 shares". */
export function partOfText(part: bigint, whole: bigint, symbol: string): string {
  if (isCoin(symbol)) return `${shareCount(part, symbol)} of ${shareCount(whole, symbol)} units of ${coinOf(symbol)}`
  return `${shareCount(part, symbol)} of ${shareCount(whole, symbol)} ${isOne(whole) ? "share" : "shares"}`
}

/** $1,234.50 from an engine string; a dash for a missing or junk value. */
export const usd = (value: string | null | undefined) => money(value)

/** An amount as a person says it: whole dollars without cents ("$160"), otherwise to the cent ("$39.50"). */
export function dollars(value: string | null | undefined): string {
  const parsed = parseDec(value)
  if (parsed === null) return "—"
  return parsed === decRound(parsed, 0) ? `$${grouped(decText(parsed))}` : money(value)
}
