import type { SourceActivity } from "../../../shared/contract"
import { reasonText } from "@/lib/reasons"
import { CARRIED_ON, HELD_FOR_OWNER, isOpenCall, isOwnerSale, orderOutcome, partOutcomes, shownOrders } from "./outcome"

// How a post ended, in the four words the page counts by, and the counts the page's cards and charts draw.

export type Bucket = "traded" | "waiting" | "skipped" | "ignored"
export const BUCKETS: Bucket[] = ["traded", "waiting", "skipped", "ignored"]
export const BUCKET_LABEL: Record<Bucket, string> = { traded: "Traded", waiting: "Waiting", skipped: "Skipped", ignored: "Ignored" }

/** Chat is ignored; a call held for the owner is waiting; an order that went out is traded; any other post was skipped. A post not read yet is none of them. */
export function bucketOf(post: SourceActivity, now: Date): Bucket | null {
  if (post.decision === "ignore") return "ignored"
  if (isOpenCall(post, now)) return "waiting"
  if (post.decision === null) return null
  const orders = post.destinations.flatMap(shownOrders).filter((o) => !isOwnerSale(o))
  // A stop resting at Alpaca counts as traded; a stop skipped because the account does not follow stops counts as skipped.
  return orders.some((o) => ["filled", "partly", "working", "stop"].includes(orderOutcome(o).kind)) ? "traded" : "skipped"
}

// ── Days, in the zone the app shows times in ──

const formatters = new Map<string | undefined, Intl.DateTimeFormat>()
function parts(at: Date, zone: string | undefined) {
  let f = formatters.get(zone)
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", hourCycle: "h23" })
    formatters.set(zone, f)
  }
  return Object.fromEntries(f.formatToParts(at).map((p) => [p.type, p.value]))
}

/** "2026-11-04": the calendar day of `at` in `zone`. */
export function dayKey(at: Date, zone: string | undefined): string {
  const p = parts(at, zone)
  return `${p.year}-${p.month}-${p.day}`
}

const hourOf = (at: Date, zone: string | undefined) => Number(parts(at, zone).hour)

/** The day `days` before (negative: after) `key`. */
export function shiftDay(key: string, days: number): string {
  const [y, m, d] = key.split("-").map(Number)
  return new Date(Date.UTC(y!, m! - 1, d! + days)).toISOString().slice(0, 10)
}

/** "Nov 4" */
export const dayName = (key: string) => new Date(`${key}T12:00:00Z`).toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" })

// ── The four cards: one day's counts, and each count by hour ──

export type Metric = "posts" | Bucket
export interface DayCounts {
  total: Record<Metric, number>
  /** Each metric's count for each hour of the day, 0 to 23. */
  hours: Record<Metric, number[]>
}

export function dayCounts(posts: SourceActivity[], key: string, zone: string | undefined, now: Date): DayCounts {
  const metrics: Metric[] = ["posts", ...BUCKETS]
  const counts: DayCounts = {
    total: Object.fromEntries(metrics.map((m) => [m, 0])) as Record<Metric, number>,
    hours: Object.fromEntries(metrics.map((m) => [m, Array<number>(24).fill(0)])) as Record<Metric, number[]>,
  }
  for (const post of posts) {
    const at = new Date(post.source_at)
    if (dayKey(at, zone) !== key) continue
    const hour = hourOf(at, zone)
    const bucket = bucketOf(post, now)
    for (const m of bucket ? (["posts", bucket] as const) : (["posts"] as const)) {
      counts.total[m]++
      counts.hours[m][hour]!++
    }
  }
  return counts
}

// ── The 30-day chart: posts per day by outcome ──

export interface DayRow extends Record<Bucket, number> {
  key: string
  label: string
}

/** The `days` days ending at `endKey`, oldest first, a row each even when nothing was posted. */
export function dayRows(posts: SourceActivity[], endKey: string, zone: string | undefined, now: Date, days = 30): DayRow[] {
  const rows = Array.from({ length: days }, (_, i): DayRow => {
    const key = shiftDay(endKey, i + 1 - days)
    return { key, label: dayName(key), traded: 0, waiting: 0, skipped: 0, ignored: 0 }
  })
  const byKey = new Map(rows.map((r) => [r.key, r]))
  for (const post of posts) {
    const bucket = bucketOf(post, now)
    const row = bucket && byKey.get(dayKey(new Date(post.source_at), zone))
    if (row && bucket) row[bucket]++
  }
  return rows
}

// ── The mix chart: outcomes by guru, or the reasons posts were skipped ──

export interface GuruMix extends Record<Bucket, number> {
  guru: string
  total: number
}

/** One row per guru with posts in `rows`, most posts first. */
export function guruMix(posts: SourceActivity[], now: Date, nameOf: (id: string | null) => string): GuruMix[] {
  const byGuru = new Map<string, GuruMix>()
  for (const post of posts) {
    const bucket = bucketOf(post, now)
    if (!bucket) continue
    const guru = nameOf(post.guru_id)
    const row = byGuru.get(guru) ?? { guru, traded: 0, waiting: 0, skipped: 0, ignored: 0, total: 0 }
    row[bucket]++
    row.total++
    byGuru.set(guru, row)
  }
  return [...byGuru.values()].sort((a, b) => b.total - a.total || a.guru.localeCompare(b.guru))
}

/** Why posts were skipped, each reason counted once per post, most common first. */
export function skipReasons(posts: SourceActivity[], now: Date, top = 5): { reason: string; count: number }[] {
  const counts = new Map<string, number>()
  for (const post of posts) {
    if (bucketOf(post, now) !== "skipped") continue
    const reasons = new Set<string>()
    for (const d of post.destinations) {
      for (const o of partOutcomes(d)) if (!CARRIED_ON.has(o) && !HELD_FOR_OWNER.has(o)) reasons.add(reasonText(o))
      if (["stale", "out_of_order"].includes(d.status)) reasons.add(reasonText(d.status))
    }
    for (const reason of reasons.size > 0 ? reasons : new Set(["Not copied"])) counts.set(reason, (counts.get(reason) ?? 0) + 1)
  }
  return [...counts].map(([reason, count]) => ({ reason, count })).sort((a, b) => b.count - a.count || a.reason.localeCompare(b.reason)).slice(0, top)
}
