const MANTISSAS = [1, 2, 2.5, 5]
/** At most this many intervals, so the value labels stay apart. */
const MAX_INTERVALS = 6

export interface BalanceAxis {
  domain: [number, number]
  ticks: number[]
  /** Cents show only when a step is under a dollar. */
  digits: 0 | 2
}

/**
 * Round value ticks around the plotted balances, from the finest step that fits, with about a tenth of the
 * plot of room above the high and below the low for their labels. Any scale: a $20 day or a $20,000 year.
 */
export function balanceAxis(values: number[]): BalanceAxis {
  const top = Math.max(...values)
  const bottom = Math.min(...values)
  const pad = Math.max((top - bottom) * 0.1, Math.abs(top) * 0.0005, 0.5)
  let best: { low: number; high: number; step: number } | null = null
  for (let exponent = -2; exponent <= 8; exponent++) {
    for (const mantissa of MANTISSAS) {
      const step = mantissa * 10 ** exponent
      const low = Math.floor((bottom - pad) / step) * step
      const high = Math.ceil((top + pad) / step) * step
      if (Math.round((high - low) / step) > MAX_INTERVALS) continue
      if (!best || high - low < best.high - best.low) best = { low, high, step }
    }
  }
  const { low, high, step } = best ?? { low: bottom, high: top, step: Math.max(top - bottom, 1) }
  const count = Math.round((high - low) / step)
  const ticks = Array.from({ length: count + 1 }, (_, i) => Number((low + i * step).toFixed(6)))
  return { domain: [Number(low.toFixed(6)), Number(high.toFixed(6))], ticks, digits: step < 1 ? 2 : 0 }
}
