import type { OrderActivity } from "../../../shared/contract"

// Amounts as a person says them (Humanize.swift, OrderAmount.swift): dollars first, shares to three places.

const usd = (digits: number) => new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", minimumFractionDigits: digits, maximumFractionDigits: digits })
const WHOLE = usd(0)
const CENTS = usd(2)

export const num = (value: string | number | null | undefined): number | null => {
  if (value === null || value === undefined || value === "") return null
  const n = Number(value)
  return Number.isFinite(n) ? n : null
}

/** Whole dollars without cents ("$160"), otherwise to the cent ("$39.50"). */
export function dollars(value: string | number | null | undefined): string {
  const n = num(value)
  if (n === null) return "—"
  return Math.round(n * 100) % 100 === 0 ? WHOLE.format(n) : CENTS.format(n)
}

/** A coin's dollar pair ("BTC/USD") rather than a stock: no stock has a slash. */
const isCoin = (symbol: string) => symbol.includes("/")
const coinName = (symbol: string) => symbol.split("/")[0]!

const isOne = (n: number) => Math.abs(n - 1) < 0.01
const places = (digits: number) => new Intl.NumberFormat("en-US", { maximumFractionDigits: digits })

/** "2.985", or "≈1" when rounding to a whole number or three places changed it. */
export function shareCount(n: number, symbol: string): string {
  if (isCoin(symbol)) return places(9).format(n)
  const whole = Math.round(n)
  const shown = Math.abs(n - whole) >= 0.01 ? Math.round(n * 1000) / 1000 : whole
  const text = places(3).format(shown)
  return shown === n ? text : `≈${text}`
}

/** "2.985 shares", "1 share", or "0.0012 units of BTC". */
export function shares(n: number, symbol: string): string {
  if (isCoin(symbol)) return `${shareCount(n, symbol)} units of ${coinName(symbol)}`
  return `${shareCount(n, symbol)} ${isOne(n) ? "share" : "shares"}`
}

/** What comes before "of" and the symbol: "2.985 shares" of PM; a coin's count alone. */
export const sharesOf = (n: number, symbol: string) => (isCoin(symbol) ? shareCount(n, symbol) : shares(n, symbol))

/** "5 of 12 shares", "0 of ≈1 share": part of an order. */
export function sharesOfOrder(part: number, quantity: number, symbol: string): string {
  if (isCoin(symbol)) return `${shareCount(part, symbol)} of ${shareCount(quantity, symbol)} units of ${coinName(symbol)}`
  return `${shareCount(part, symbol)} of ${shareCount(quantity, symbol)} ${isOne(quantity) ? "share" : "shares"}`
}

/** An amount of a stock, dollar first: "$200 of PM stock". */
export const amountOf = (amount: string, symbol: string) => `${amount} of ${symbol} stock`

/** Whole dollars without cents, otherwise to the cent, after rounding to the cent. */
export const orderDollars = (value: number) => dollars(Math.round(value * 100) / 100)

export function filledUsd(order: OrderActivity): number | null {
  const [filled, price] = [num(order.filled_quantity), num(order.average_fill_price)]
  return filled && filled > 0 && price !== null ? filled * price : null
}

/** The order's budget, or its shares at its limit when the budget is not on record. */
export function plannedUsd(order: OrderActivity): number | null {
  const budget = num(order.budget_usd)
  if (budget !== null) return budget
  const [quantity, limit] = [num(order.quantity), num(order.limit_price)]
  return quantity !== null && limit !== null ? quantity * limit : null
}

/** "$199.82 of PM stock", when anything filled. */
export const filledAmount = (order: OrderActivity): string | null => {
  const n = filledUsd(order)
  return n === null ? null : amountOf(CENTS.format(n), order.symbol)
}

/** "$200 of PM stock". */
export const plannedAmount = (order: OrderActivity): string | null => {
  const n = plannedUsd(order)
  return n === null ? null : amountOf(orderDollars(n), order.symbol)
}

/** 45 seconds, 3 minutes, 2 h 5 min. */
export function duration(seconds: number): string {
  const s = Math.max(0, Math.round(seconds))
  if (s < 90) return `${s} ${s === 1 ? "second" : "seconds"}`
  const minutes = Math.round(s / 60)
  if (minutes < 120) return `${minutes} minutes`
  const hours = Math.floor(minutes / 60)
  return minutes % 60 ? `${hours} h ${minutes % 60} min` : `${hours} h`
}

/** 0.1666… reads as "1/6": an engine fraction with a small denominator, else a few digits. */
export function fraction(value: string): string {
  const n = num(value)
  if (n === null) return value
  for (let denominator = 1; denominator <= 100; denominator++) {
    const numerator = Math.round(n * denominator)
    if (numerator > 0 && Math.abs(numerator / denominator - n) < 1e-9) return denominator === 1 ? String(numerator) : `${numerator}/${denominator}`
  }
  return Number(n.toPrecision(4)).toString()
}
