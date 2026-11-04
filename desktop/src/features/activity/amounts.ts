import type { OrderActivity } from "../../../shared/contract"
import { money } from "@/lib/format"
import { dollars } from "@/lib/quantity"

// What an order cost, as a person says it (OrderAmount.swift). Share counts and plain dollars are in lib/quantity.

export const num = (value: string | number | null | undefined): number | null => {
  if (value === null || value === undefined || value === "") return null
  const n = Number(value)
  return Number.isFinite(n) ? n : null
}

/** An amount of a stock, dollar first: "$200 of PM stock". */
export const amountOf = (amount: string, symbol: string) => `${amount} of ${symbol} stock`

/** Whole dollars without cents, otherwise to the cent, after rounding to the cent. */
export const orderDollars = (value: number) => dollars(String(Math.round(value * 100) / 100))

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
  return n === null ? null : amountOf(money(n), order.symbol)
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
