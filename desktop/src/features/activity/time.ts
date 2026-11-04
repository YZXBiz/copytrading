// Times as a person reads them on a post: to the second, since calls land seconds apart.

/** Nov 3, 1:41:33 PM */
export const postTime = (iso: string) =>
  new Date(iso).toLocaleString("en-US", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit", second: "2-digit" })

/** 1:41:33 PM */
export const clockTime = (iso: string) => new Date(iso).toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit", second: "2-digit" })

/** The clock for today, the day and clock before that. */
export function feedTime(iso: string, now: Date): string {
  const at = new Date(iso)
  return at.toDateString() === now.toDateString()
    ? clockTime(iso)
    : at.toLocaleString("en-US", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })
}

const startOfDay = (date: Date) => new Date(date.getFullYear(), date.getMonth(), date.getDate())

/** Today, Yesterday, or "Monday, Nov 2". */
export function dayLabel(iso: string, now: Date): string {
  const days = Math.round((startOfDay(now).getTime() - startOfDay(new Date(iso)).getTime()) / 86_400_000)
  if (days === 0) return "Today"
  if (days === 1) return "Yesterday"
  return new Date(iso).toLocaleDateString("en-US", { weekday: "long", month: "short", day: "numeric" })
}

/** The owner's calendar day around `now`, as the engine's day-stats window. */
export function dayWindow(now: Date): { day_start: string; day_end: string } {
  const start = startOfDay(now)
  return { day_start: start.toISOString(), day_end: new Date(start.getFullYear(), start.getMonth(), start.getDate() + 1).toISOString() }
}
