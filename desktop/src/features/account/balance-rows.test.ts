import { describe, expect, it } from "vitest"
import { balanceRows } from "./balance-rows"

const at = (day: number) => `2026-10-${String(day).padStart(2, "0")}T20:00:00Z`

describe("balanceRows", () => {
  it("marks the highest and lowest close and reads each against the range's opening balance", () => {
    const rows = balanceRows([
      { at: at(1), equity: 3000 },
      { at: at(2), equity: 3068.26 },
      { at: at(3), equity: 2715.27 },
      { at: at(4), equity: 2800 },
    ])
    expect(rows.map((r) => r.marker)).toEqual([null, "high", "low", null])
    expect(rows[2]!.sinceStart).toBeCloseTo(-284.73, 2)
    expect(rows[2]!.sinceStartRatio).toBeCloseTo(-0.09491, 4)
    expect(rows[0]!.sinceStart).toBe(0)
  })

  it("marks nothing on a flat range", () => {
    expect(balanceRows([{ at: at(1), equity: 2700 }, { at: at(2), equity: 2700 }]).map((r) => r.marker)).toEqual([null, null])
  })

  it("keeps the first of equal highs and has no rows for no points", () => {
    expect(balanceRows([{ at: at(1), equity: 5 }, { at: at(2), equity: 9 }, { at: at(3), equity: 9 }]).map((r) => r.marker)).toEqual(["low", "high", null])
    expect(balanceRows([])).toEqual([])
  })
})
