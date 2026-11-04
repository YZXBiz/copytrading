// Exact decimals for share counts and prices. A float would send the broker 0.30000000000000004,
// so every quantity that goes to the engine is built here and written back as a decimal string.

const SCALE = 30
export const DEC_ONE = 10n ** BigInt(SCALE)

/** An engine decimal string as a scaled integer, or null when it is not a plain decimal. */
export function parseDec(text: string | null | undefined): bigint | null {
  const match = /^(-?)(\d+)(?:\.(\d+))?$/.exec((text ?? "").trim())
  if (!match) return null
  const units = BigInt(match[2]! + (match[3] ?? "").slice(0, SCALE).padEnd(SCALE, "0"))
  return match[1] ? -units : units
}

export const decMul = (a: bigint, b: bigint) => (a * b) / DEC_ONE

/** Rounds toward zero to `places` decimals: a sale never asks for more than the lot holds. */
export function decDown(value: bigint, places: number): bigint {
  const step = 10n ** BigInt(SCALE - places)
  return (value / step) * step
}

/** Rounds half away from zero to `places` decimals. */
export function decRound(value: bigint, places: number): bigint {
  const step = 10n ** BigInt(SCALE - places)
  const half = step / 2n
  return value < 0n ? -(((-value + half) / step) * step) : ((value + half) / step) * step
}

/** The decimal string the engine takes: no exponent, no trailing zeros. */
export function decText(value: bigint): string {
  const abs = value < 0n ? -value : value
  const fraction = (abs % DEC_ONE).toString().padStart(SCALE, "0").replace(/0+$/, "")
  return `${value < 0n ? "-" : ""}${abs / DEC_ONE}${fraction ? `.${fraction}` : ""}`
}
