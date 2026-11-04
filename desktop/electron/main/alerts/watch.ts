import type { SourceActivity, TradingRunState, TradingStatus } from "../../../shared/contract"

// What the owner is told about, decided from what the engine reports: FillWatch.swift, StoppedWatch.swift,
// CopyingMemory.swift, TradingHours.swift. Pure: the monitor feeds them and sends what they return.

/** One order, with who it was copied from and where; the owner's own sale names no guru. */
export interface Fill {
  clientId: string
  side: string
  symbol: string
  shares: string
  price: string | null
  accountId: string
  guruId: string | null
  byOwner: boolean
}

export interface FillNews {
  sent: Fill[]
  filled: Fill[]
}

/** Statuses of an order the broker has taken and is working; "prepared" has not gone out yet. */
const WORKING = new Set(["accepted", "pending_new", "accepted_for_bidding", "new", "partially_filled", "held"])

/** A lot the owner sold by hand: tied to a post, but nobody copied it. */
const isOwnerSale = (clientId: string) => clientId.startsWith("lotsale-")

/**
 * Which copied orders were newly sent or newly filled since the last read, so each is said once. An order counts only if
 * it was sent or filled after the app opened, so a restart never re-announces the day.
 */
export class FillWatch {
  private readonly sent = new Set<string>()
  private readonly filled = new Set<string>()

  constructor(private readonly openedAt: Date = new Date()) {}

  /** An order that went out and filled between two reads is said once, as its fill. */
  news(activity: SourceActivity[]): FillNews {
    const news: FillNews = { sent: [], filled: [] }
    for (const post of activity) {
      for (const destination of post.destinations) {
        for (const order of destination.orders ?? []) {
          const fill = (shares: string, price: string | null): Fill => ({
            clientId: order.client_id,
            side: order.side,
            symbol: order.symbol,
            shares,
            price,
            accountId: destination.account_id,
            guruId: isOwnerSale(order.client_id) ? null : post.guru_id,
            byOwner: isOwnerSale(order.client_id),
          })
          const endedWithFills = order.status !== "prepared" && !WORKING.has(order.status) && Number(order.filled_quantity) > 0
          if (endedWithFills) {
            if (this.filled.has(order.client_id)) continue
            this.filled.add(order.client_id)
            this.sent.add(order.client_id)
            if (this.isSince(order.ended_at ?? order.submitted_at)) news.filled.push(fill(order.filled_quantity, order.average_fill_price))
          } else if (WORKING.has(order.status)) {
            if (this.sent.has(order.client_id)) continue
            this.sent.add(order.client_id)
            if (this.isSince(order.submitted_at)) news.sent.push(fill(order.quantity, order.limit_price))
          }
        }
      }
    }
    return news
  }

  private isSince(stamp: string | null | undefined): boolean {
    const at = stamp ? Date.parse(stamp) : Number.NaN
    return at >= this.openedAt.getTime()
  }
}

/**
 * Accounts the engine stopped on its own since the last read: they ran, and now have failed (or the whole run failed
 * and they are not running). Each stop is returned once; an account has to run again to stop again.
 */
export class StoppedWatch {
  private running = new Set<string>()

  stopped(status: TradingStatus | null): string[] {
    if (!status) {
      this.running = new Set()
      return []
    }
    const accounts = status.accounts ?? []
    const runFailed = status.state === "failed"
    const stopped = accounts.filter((a) => this.running.has(a.id) && (a.state === "failed" || (runFailed && a.state !== "running")))
    this.running = new Set(accounts.filter((a) => a.state === "running").map((a) => a.id))
    return stopped.map((a) => a.id).sort()
  }
}

/**
 * Whether copying was on the last time CopyTrading looked, so the next launch can say it came back paused. Every status
 * the engine reports updates it, so a quit, a crash and a restart all leave it as it was; only a status that says copying
 * is paused (the owner pressed Stop) clears it. No status, and a failed start, change nothing.
 */
export class CopyingMemory {
  constructor(
    private on: boolean,
    private readonly save: (on: boolean) => void,
  ) {}

  get wasOn(): boolean {
    return this.on
  }

  observe(state: TradingRunState | null): void {
    const next = state === "running" || state === "degraded" || state === "starting" ? true : state === "paused" || state === "pausing" ? false : this.on
    if (next === this.on) return
    this.on = next
    this.save(next)
  }
}

/** US stocks trade from 4:00 AM to 8:00 PM New York time, Monday to Friday. Holidays are not counted. */
export function inTradingHours(at: Date): boolean {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", weekday: "short", hour: "numeric", hourCycle: "h23" }).formatToParts(at)
  const weekday = parts.find((p) => p.type === "weekday")?.value ?? ""
  const hour = Number(parts.find((p) => p.type === "hour")?.value)
  return ["Mon", "Tue", "Wed", "Thu", "Fri"].includes(weekday) && hour >= 4 && hour < 20
}

const HALF_HOUR_MS = 30 * 60_000

/** Paused after copying was on at the last quit: said at once, then every half hour while it stays paused in trading hours. */
export function copyingStoppedDue(announcedAt: Date | null, now: Date): boolean {
  return announcedAt === null || (now.getTime() - announcedAt.getTime() >= HALF_HOUR_MS && inTradingHours(now))
}
