/** One close of the account's balance, as the engine reports it. */
export type BalancePoint = { at: string; equity: number }

/** One plotted close and what the tooltip reads beside it. */
export type BalanceRow = {
  /** The category key: the point's own ISO time. */
  key: string
  time: number
  balance: number
  sinceStart: number
  sinceStartRatio: number
}

export type RangeStats = {
  open: number
  close: number
  change: number
  changeRatio: number
}

/** The range's points as rows, each read against the range's opening balance. */
export function balanceRows(points: BalancePoint[]): BalanceRow[] {
  if (points.length === 0) return []
  const open = points[0]!.equity
  return points.map((point) => ({
    key: point.at,
    time: Date.parse(point.at),
    balance: point.equity,
    sinceStart: point.equity - open,
    sinceStartRatio: open > 0 ? point.equity / open - 1 : 0,
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
  }
}
