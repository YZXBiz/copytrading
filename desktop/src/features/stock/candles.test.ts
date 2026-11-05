import { describe, expect, it } from "vitest"
import type { DailyBar } from "../../../shared/contract"
import { STOCK_RANGES, sessionOf, toCandles } from "./candles"

const bar = (at: string, open: string, high: string, low: string, close: string, volume = 1000): DailyBar => ({ at, open, high, low, close, volume })

describe("toCandles", () => {
  const bars = [bar("2026-10-30T04:00:00Z", "40", "41", "39.5", "40.5"), bar("2026-11-02T05:00:00Z", "40.5", "42", "40", "41.25", 2500), bar("2026-11-03T05:00:00Z", "41.25", "41.5", "40.9", "41")]

  it("reads each bar's prices as numbers and keeps its volume", () => {
    expect(toCandles(bars)[1]).toMatchObject({ o: 40.5, h: 42, l: 40, c: 41.25, v: 2500 })
  })

  it("dates a bar by its New York trading day, which a midnight there puts on the same day in UTC", () => {
    expect(toCandles(bars).map((c) => c.label)).toEqual(["Oct 30, 2026", "Nov 2, 2026", "Nov 3, 2026"])
  })

  it("marks where a month starts, for the axis", () => {
    const [first, second, third] = toCandles(bars)
    expect([first!.rank, second!.rank, third!.rank]).toEqual([2, 2, 1])
    expect([first!.tick, second!.tick, third!.tick]).toEqual(["Oct", "Nov", "Nov 3"])
  })

  it("names January's tick for its year", () => {
    expect(toCandles([bar("2026-01-02T05:00:00Z", "1", "1", "1", "1")])[0]!.tick).toBe("2026")
  })
})

describe("sessionOf", () => {
  it("is the last bar's figures against the close before it", () => {
    const candles = toCandles([bar("2026-11-02T05:00:00Z", "40.5", "42", "40", "41.25"), bar("2026-11-03T05:00:00Z", "41.25", "41.5", "40.9", "41", 800)])
    expect(sessionOf(candles)).toEqual({ open: 41.25, high: 41.5, low: 40.9, volume: 800, previousClose: 41.25, close: 41 })
  })

  it("is nothing until there are two bars", () => {
    expect(sessionOf([])).toBeNull()
    expect(sessionOf(toCandles([bar("2026-11-03T05:00:00Z", "1", "1", "1", "1")]))).toBeNull()
  })
})

describe("STOCK_RANGES", () => {
  it("offers one, six and twelve months, each with fifty bars of warm-up", () => {
    expect(STOCK_RANGES.map((r) => [r.value, r.spec.label, r.spec.count, r.spec.warm])).toEqual([
      ["month", "1M", 21, 50],
      ["six_months", "6M", 126, 50],
      ["year", "1Y", 252, 50],
    ])
  })
})
