// When a waiting call can still be copied (WaitingCall.deadline, TradingDeadlineText.swift): 20:00 New York time
// on its trading day, said in the owner's own time zone with the zone's short name. The account page and the
// Activity screen both decide from this one module.

const NEW_YORK = "America/New_York"

const newYorkParts = new Intl.DateTimeFormat("en-US", { timeZone: NEW_YORK, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", hourCycle: "h23" })

/** The New York trading day an instant belongs to; from 20:00 it is the next day's, as the engine's `trade_date` counts it. */
export function tradingDay(instant: Date): string {
  const { year, month, day, hour } = Object.fromEntries(newYorkParts.formatToParts(instant).map((p) => [p.type, Number(p.value)])) as Record<"year" | "month" | "day" | "hour", number>
  return new Date(Date.UTC(year, month - 1, day + (hour >= 20 ? 1 : 0))).toISOString().slice(0, 10)
}

const hourIn = (instant: Date, timeZone: string) =>
  Number(new Intl.DateTimeFormat("en-US", { timeZone, hour: "2-digit", hourCycle: "h23" }).format(instant))

/** 20:00 New York time on the trading day `sourceAt` belongs to (from 20:00 a post belongs to the next day). */
export function endOfTradingDay(sourceAt: string): Date {
  const [year, month, day] = tradingDay(new Date(sourceAt)).split("-").map(Number) as [number, number, number]
  // New York is four or five hours behind UTC; the one that lands on 20:00 there is the deadline.
  for (const behind of [4, 5]) {
    const candidate = new Date(Date.UTC(year, month - 1, day, 20 + behind))
    if (hourIn(candidate, NEW_YORK) === 20) return candidate
  }
  throw new Error("No 20:00 in New York on that day.")
}

const dayIn = (instant: Date, timeZone: string | undefined) => instant.toLocaleDateString("en-CA", { timeZone })

/** "Deadline today: 5:00 PM PST", "Deadline tomorrow: 5:00 PM PST", or "Deadline on Fri 5:00 PM PST" further out. */
export function deadlineText(deadline: Date, now: Date, timeZone?: string): string {
  const clock = deadline.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit", timeZone, timeZoneName: "short" })
  const day = dayIn(deadline, timeZone)
  if (day === dayIn(now, timeZone)) return `Deadline today: ${clock}`
  const [y, m, d] = dayIn(now, timeZone).split("-").map(Number) as [number, number, number]
  if (day === new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10)) return `Deadline tomorrow: ${clock}`
  return `Deadline on ${deadline.toLocaleDateString("en-US", { weekday: "short", timeZone })} ${clock}`
}
