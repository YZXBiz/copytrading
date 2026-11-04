// Display formatting for engine values. Decimals arrive as strings; null or junk shows an em dash.

type Num = string | number | null | undefined

const MINUS = "−"
const DASH = "—"
const usd = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" })
const shareCount = new Intl.NumberFormat("en-US", { maximumFractionDigits: 6 })

function parse(value: Num): number | null {
  if (value === null || value === undefined || value === "") return null
  const n = Number(value)
  return Number.isFinite(n) ? n : null
}

/** $2,700.08 */
export function money(value: Num): string {
  const n = parse(value)
  return n === null ? DASH : usd.format(n)
}

/** +$12.00, −$15.19, $0.00: the sign is always the real one, and a zero has none. */
export function signedMoney(value: Num): string {
  const n = parse(value)
  if (n === null) return DASH
  const text = usd.format(Math.abs(n))
  return n > 0 ? `+${text}` : n < 0 ? `${MINUS}${text}` : text
}

/** A fraction as a percent: 0.2976 → 29.8% */
export function percent(fraction: Num, digits = 1): string {
  const n = parse(fraction)
  return n === null ? DASH : `${(n * 100).toFixed(digits)}%`
}

/** −29.8%, +46.5%, 0.0% */
export function signedPercent(fraction: Num, digits = 1): string {
  const n = parse(fraction)
  if (n === null) return DASH
  const text = `${(Math.abs(n) * 100).toFixed(digits)}%`
  return Number(text.slice(0, -1)) === 0 ? text : n > 0 ? `+${text}` : `${MINUS}${text}`
}

/** 6.679793 shares, never more than six decimals, no trailing zeros. */
export function shares(value: Num): string {
  const n = parse(value)
  return n === null ? DASH : shareCount.format(n)
}

type Zone = { timeZone?: string }

/** Nov 3, 1:41 PM */
export function dateTime(iso: string, { timeZone }: Zone = {}): string {
  return new Date(iso).toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZone,
  })
}

/** 1:41 PM */
export function timeOfDay(iso: string, { timeZone }: Zone = {}): string {
  return new Date(iso).toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit", timeZone })
}

/** Nov 3 */
export function monthDay(iso: string, { timeZone }: Zone = {}): string {
  return new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone })
}

/** just now, 5 min ago, 3 h ago, 2 d ago */
export function ago(iso: string, now: Date = new Date()): string {
  const seconds = Math.max(0, (now.getTime() - new Date(iso).getTime()) / 1000)
  if (seconds < 60) return "just now"
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min ago`
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} h ago`
  return `${Math.floor(seconds / 86400)} d ago`
}
