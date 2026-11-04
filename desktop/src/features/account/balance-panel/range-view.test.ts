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

  it("marks the highest and lowest close and reads each against the range's opening balance", () => {
    expect(rows.map((r) => r.marker)).toEqual([null, "high", "low", null])
    expect(rows[2]!.sinceStart).toBeCloseTo(-284.73, 2)
    expect(rows[2]!.sinceStartRatio).toBeCloseTo(-0.09491, 4)
    expect(rows[0]!.sinceStart).toBe(0)
  })

  it("carries the range's average on every row and the stats read the ends", () => {
    expect(rows.every((r) => r.average === rows[0]!.average)).toBe(true)
    expect(rows[0]!.average).toBeCloseTo(2895.88, 2)
    expect(rangeStats(rows)).toMatchObject({ open: 3000, close: 2800, change: -200 })
    expect(rangeStats(rows).changeRatio).toBeCloseTo(-0.06667, 4)
  })

  it("marks nothing on a flat range, and has no rows for no points", () => {
    expect(balanceRows([{ at: at(1), equity: 2700 }, { at: at(2), equity: 2700 }]).map((r) => r.marker)).toEqual([null, null])
    expect(balanceRows([])).toEqual([])
  })
})
