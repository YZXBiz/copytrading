import { describe, expect, it } from "vitest"
import { balanceRows, rangeStats } from "./range-view"

const at = (day: number) => `2026-10-${String(day).padStart(2, "0")}T20:00:00Z`

describe("balanceRows", () => {
  const rows = balanceRows([
    { at: at(1), equity: 3000 },
    { at: at(2), equity: 3068.26 },
    { at: at(3), equity: 2715.27 },
    { at: at(4), equity: 2800 },
  ])

  it("reads each close against the range's opening balance", () => {
    expect(rows[2]!.sinceStart).toBeCloseTo(-284.73, 2)
    expect(rows[2]!.sinceStartRatio).toBeCloseTo(-0.09491, 4)
    expect(rows[0]!.sinceStart).toBe(0)
  })

  it("reads the range's ends for the stats, and has no rows for no points", () => {
    expect(rangeStats(rows)).toMatchObject({ open: 3000, close: 2800, change: -200 })
    expect(rangeStats(rows).changeRatio).toBeCloseTo(-0.06667, 4)
    expect(balanceRows([])).toEqual([])
  })
})
