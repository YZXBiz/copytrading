import type { AccountPolicy } from "../../../shared/contract"

// What a guru's calls come to in the account they copy into (ADR-0010; SizingSummary.swift, copiedBudgetUSD).
// Dollar amounts are BigInt counts of 1e-10 dollars, so the rounding is the engine's and never a float's.

const SCALE = 10n ** 10n
const CENT = SCALE / 100n

/** A decimal string with at most ten places as 1e-10 dollars; null for anything else. */
function parse(value: string): bigint | null {
  const match = /^(\d+)(?:\.(\d{1,10}))?$/.exec(value.trim())
  return match ? BigInt(match[1]!) * SCALE + BigInt((match[2] ?? "").padEnd(10, "0")) : null
}

const floorToCents = (amount: bigint) => amount - (amount % CENT)

export interface Fraction {
  numerator: bigint
  denominator: bigint
}

/**
 * What a call asks for: its share of the full position, rounded to ten places and then down to the cent; or, with no
 * size, `unsizedUsd` (never more than the full position). Null when nothing would be bought.
 */
export function copiedBudget(fullPositionUsd: string, fraction: Fraction | null, unsizedUsd: string | null): bigint | null {
  const full = parse(fullPositionUsd)
  if (full === null || full <= 0n) return null
  if (!fraction) {
    const dollars = unsizedUsd === null ? null : parse(unsizedUsd)
    if (dollars === null || dollars <= 0n) return null
    const cents = floorToCents(dollars < full ? dollars : full)
    return cents > 0n ? cents : null
  }
  if (fraction.numerator <= 0n || fraction.numerator > fraction.denominator) return null
  // Round half up to ten places: (a * n / d) with the remainder deciding.
  const scaled = full * fraction.numerator
  const product = scaled / fraction.denominator + (2n * (scaled % fraction.denominator) >= fraction.denominator ? 1n : 0n)
  const cents = floorToCents(product)
  return cents > 0n ? cents : null
}

/** 1e-10 dollars as a plain decimal with two places: "166.66". */
export const decimal = (amount: bigint): string => {
  const cents = amount / CENT
  return `${cents / 100n}.${String(cents % 100n).padStart(2, "0")}`
}

/** Whole dollars without cents, as a person says an amount: "$40", "$41.66". */
export const dollars = (amount: bigint): string => {
  const text = decimal(amount)
  return `$${BigInt(text.slice(0, -3)).toLocaleString("en-US")}${text.endsWith(".00") ? "" : text.slice(-3)}`
}

export interface SizingFigure {
  label: string
  amount: string
  /** What the call asked for, when the largest single buy cut it down to `amount`. */
  cutFrom: string | null
}

export interface Sizing {
  figures: SizingFigure[]
  /** The largest single buy cuts at least one figure. */
  note: string | null
  /** The full position is above the account's maximum per stock, so a buy stops at that limit. */
  warning: string | null
}

/** Null until the guru has a full position: their own, or the account's maximum per stock. */
export function sizing(fullPositionUsd: string, policy: AccountPolicy | undefined): Sizing | null {
  const maximum = policy?.max_symbol_usd.trim() ?? ""
  const fullText = fullPositionUsd.trim() || maximum
  const full = parse(fullText)
  const parsedCap = policy ? parse(policy.max_order_usd) : null
  const cap = parsedCap !== null && parsedCap > 0n ? parsedCap : null
  const capText = cap === null ? null : policy!.max_order_usd
  const sixth = copiedBudget(fullText, { numerator: 1n, denominator: 6n }, capText)
  const half = copiedBudget(fullText, { numerator: 1n, denominator: 2n }, capText)
  // A post with no size buys the largest single buy; without one, the full position.
  const unsized = copiedBudget(fullText, null, capText ?? fullText)
  if (full === null || full <= 0n || sixth === null || half === null || unsized === null) return null
  const figure = (label: string, asked: bigint): SizingFigure => {
    const trimmed = cap !== null && asked > cap
    return { label, amount: dollars(trimmed ? cap! : asked), cutFrom: trimmed ? dollars(asked) : null }
  }
  const figures = [figure("A 1/6 call", sixth), figure("A 1/2 call", half), figure("No size given", unsized)]
  const limit = parse(maximum)
  return {
    figures,
    note: figures.some((f) => f.cutFrom) && cap !== null ? `Your largest single buy, ${dollars(cap)}, caps any one buy.` : null,
    warning: limit !== null && full > limit ? `Above this account's ${dollars(limit)} limit for one stock: buys stop there.` : null,
  }
}
