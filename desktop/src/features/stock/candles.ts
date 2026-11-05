import type { Candle, RangeId, RangeSpec } from "@/components/arc/blocks/market-terminal/market-terminal-data"
import type { DailyBar, DailyRange } from "../../../shared/contract"

/** The ranges the chart offers, with the bars each shows by default; the fifty before it only warm the averages and give panning somewhere to go. */
export const STOCK_RANGES: { value: DailyRange; spec: RangeSpec }[] = [
  { value: "month", spec: { id: "1M", label: "1M", interval: "daily", count: 21, warm: 50, minutes: 0 } },
  { value: "six_months", spec: { id: "6M", label: "6M", interval: "daily", count: 126, warm: 50, minutes: 0 } },
  { value: "year", spec: { id: "1Y", label: "1Y", interval: "daily", count: 252, warm: 50, minutes: 0 } },
]

export const rangeOf = (id: RangeId) => STOCK_RANGES.find((r) => r.spec.id === id)!

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

/** A daily bar's date is the New York trading day it stands for, whatever zone the window is in. */
const day = (at: string) => {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", year: "numeric", month: "numeric", day: "numeric" }).formatToParts(new Date(at))
  const get = (type: string) => Number(parts.find((p) => p.type === type)!.value)
  return { y: get("year"), m: get("month") - 1, d: get("day") }
}

/** The chart's candles from the engine's daily bars, oldest first: the readout date, the axis tick, and where a month starts. */
export function toCandles(bars: DailyBar[]): Candle[] {
  return bars.map((bar, i) => {
    const { y, m, d } = day(bar.at)
    const before = i > 0 ? day(bars[i - 1]!.at) : null
    const newMonth = before === null || before.m !== m
    return {
      o: Number(bar.open),
      h: Number(bar.high),
      l: Number(bar.low),
      c: Number(bar.close),
      v: bar.volume,
      label: `${MONTHS[m]} ${d}, ${y}`,
      tick: newMonth ? (m === 0 ? String(y) : MONTHS[m]!) : `${MONTHS[m]} ${d}`,
      rank: newMonth ? 2 : 1,
      today: false,
    }
  })
}

/** What the page says about the last session: its open, high, low and volume, and the close before it. Null without two bars. */
export function sessionOf(candles: Candle[]) {
  const last = candles[candles.length - 1]
  const before = candles[candles.length - 2]
  return last && before ? { open: last.o, high: last.h, low: last.l, volume: last.v, previousClose: before.c, close: last.c } : null
}
