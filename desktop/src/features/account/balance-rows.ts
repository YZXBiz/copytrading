export interface BalancePoint {
  at: string
  equity: number
}

/** One plotted close and what its readout says beside it (chart-4's BalanceRow, without the benchmark). */
export interface BalanceRow {
  /** The category key: the point's own time. */
  key: string
  balance: number
  sinceStart: number
  sinceStartRatio: number
  /** The range's highest and lowest close, marked on the line; null on the rest, and on a flat range. */
  marker: "high" | "low" | null
}

export function balanceRows(points: BalancePoint[]): BalanceRow[] {
  const opened = points[0]?.equity ?? 0
  const high = points.reduce((best, p, i) => (p.equity > points[best]!.equity ? i : best), 0)
  const low = points.reduce((best, p, i) => (p.equity < points[best]!.equity ? i : best), 0)
  return points.map((p, i) => ({
    key: p.at,
    balance: p.equity,
    sinceStart: p.equity - opened,
    sinceStartRatio: opened > 0 ? p.equity / opened - 1 : 0,
    marker: high === low ? null : i === high ? "high" : i === low ? "low" : null,
  }))
}
