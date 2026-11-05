import type { DailyBar, DailyRange } from "../../../shared/contract"

// SYNTHETIC daily bars (the captured account's engine reads were not taken for daily candles): a seeded walk of
// weekdays ending on the pinned clock's Nov 3, 2026 at the price the fixture quotes, so the stock page can be
// captured with candles, volume and both averages. The range asks for its own stretch plus fifty trading days.
const DAYS: Record<DailyRange, number> = { month: 21, six_months: 126, year: 252 }
const WARM = 50

function walk(symbol: string): DailyBar[] {
  let state = [...symbol].reduce((hash, char) => Math.imul(hash ^ char.charCodeAt(0), 16777619) >>> 0, 2166136261)
  const random = () => {
    state = (state + 0x6d2b79f5) | 0
    let t = Math.imul(state ^ (state >>> 15), 1 | state)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
  const days: Date[] = []
  for (let day = new Date(Date.UTC(2026, 10, 3, 5)); days.length < DAYS.year + WARM; day = new Date(day.getTime() - 86_400_000)) {
    if (day.getUTCDay() !== 0 && day.getUTCDay() !== 6) days.push(day)
  }
  days.reverse()
  // Walk backward from the quote so the last close is the price the page shows.
  const closes: number[] = []
  let price = 40.43
  for (let i = days.length - 1; i >= 0; i--) {
    closes[i] = price
    price /= 1 + (random() - 0.5) * 0.07 + 0.0012 * Math.sin(i / 17)
  }
  return days.map((day, i) => {
    const close = closes[i]!
    const open = i === 0 ? close : closes[i - 1]! * (1 + (random() - 0.5) * 0.012)
    const high = Math.max(open, close) * (1 + random() * 0.02)
    const low = Math.min(open, close) * (1 - random() * 0.02)
    return {
      at: day.toISOString(),
      open: open.toFixed(2),
      high: high.toFixed(2),
      low: low.toFixed(2),
      close: close.toFixed(2),
      volume: Math.round(900_000 * (0.6 + random() * 0.9)),
    }
  })
}

const cache = new Map<string, DailyBar[]>()

/** The range's bars and the fifty before them, oldest first. */
export function dailyBars(symbol: string, range: DailyRange): DailyBar[] {
  const all = cache.get(symbol) ?? walk(symbol)
  cache.set(symbol, all)
  return all.slice(-(DAYS[range] + WARM))
}
