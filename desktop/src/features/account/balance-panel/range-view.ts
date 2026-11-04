/** One close of the account's balance, as the engine reports it. */
export type BalancePoint = { at: string; equity: number }

/** One plotted close and what the tooltip reads beside it. */
export type BalanceRow = {
  /** The category key: the point's own ISO time. */
  key: string
  time: number
  balance: number
  /** The range's average, the same on every row: a flat series that
   *  moves with the line when the range changes. */
  average: number
  sinceStart: number
  sinceStartRatio: number
  marker: "high" | "low" | null
}

export type RangeStats = {
  open: number
  close: number
  change: number
  changeRatio: number
  average: number
}

/** The range's points as rows: the high and the lowest close marked (none on a flat range). */
export function balanceRows(points: BalancePoint[]): BalanceRow[] {
  if (points.length === 0) return []
  const open = points[0]!.equity
  const balances = points.map((p) => p.equity)
  const high = balances.indexOf(Math.max(...balances))
  const low = balances.indexOf(Math.min(...balances))
  const average = balances.reduce((total, balance) => total + balance, 0) / balances.length
  return points.map((point, index) => ({
    key: point.at,
    time: Date.parse(point.at),
    balance: point.equity,
    average,
    sinceStart: point.equity - open,
    sinceStartRatio: open > 0 ? point.equity / open - 1 : 0,
    marker: high === low ? null : index === high ? "high" : index === low ? "low" : null,
  }))
}

/** The figures the header reads off the range. */
export function rangeStats(rows: BalanceRow[]): RangeStats {
  const open = rows[0]!
  const close = rows[rows.length - 1]!
  return {
    open: open.balance,
    close: close.balance,
    change: close.balance - open.balance,
    changeRatio: open.balance > 0 ? close.balance / open.balance - 1 : 0,
    average: open.average,
  }
}
