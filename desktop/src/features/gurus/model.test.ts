import { describe, expect, it } from "vitest"
import type { AccountOverview, DestinationActivity, GuruDayStats, OrderActivity, SourceActivity, TradingConfiguration } from "../../../shared/contract"
import { buildFeed, guruAccountOutcomes, guruDirectory, guruHoldings, guruStats, includesEntry } from "./model"

const NOW = new Date("2026-11-03T21:00:00Z")

const config = {
  accounts: [
    { id: "paper-1", environment: "paper" },
    { id: "live-1", environment: "live" },
  ],
  profiles: [
    { guru_id: "z", display_name: "Zhao", profile_revision: "rev-z" },
    { guru_id: "a", display_name: "Ann", profile_revision: "rev-a" },
  ],
  routes: [
    { guru_id: "z", profile_revision: "rev-z", connections: [{ account_id: "paper-1" }, { account_id: "live-1" }] },
    { guru_id: "z", profile_revision: "rev-z", connections: [{ account_id: "paper-1" }] },
    { guru_id: "a", profile_revision: "rev-a", connections: [{ account_id: "paper-1" }] },
  ],
} as unknown as TradingConfiguration

const order = (status: string): OrderActivity => ({
  client_id: "sig-1",
  symbol: "PM",
  side: "buy",
  status,
  quantity: "1",
  filled_quantity: status === "filled" ? "1" : "0",
  limit_price: "100",
  average_fill_price: status === "filled" ? "100" : null,
  broker_id: null,
  created_at: "2026-11-03T17:00:05Z",
  instruction_index: 0,
})

const dest = (status: string, outcomes: string[], orders: OrderActivity[] = []): DestinationActivity => ({ account_id: "paper-1", environment: "paper", status, instruction_outcomes: outcomes, orders })

const post = (sequence: number, at: string, p: Partial<SourceActivity> = {}): SourceActivity => ({
  sequence,
  source_at: at,
  text: `post ${sequence}`,
  decision: "trade",
  guru_id: "z",
  instructions: [],
  destinations: [],
  ...p,
})

describe("guruDirectory", () => {
  it("names each guru by profile, sorted, with each account once", () => {
    const gurus = guruDirectory(config)
    expect(gurus.map((g) => g.name)).toEqual(["Ann", "Zhao"])
    expect(gurus[1]!.accounts).toEqual([
      { id: "paper-1", environment: "paper" },
      { id: "live-1", environment: "live" },
    ])
  })

  it("is empty without a saved setup", () => {
    expect(guruDirectory(null)).toEqual([])
  })
})

describe("guruAccountOutcomes", () => {
  it("says traded for a fill, working for a resting order, not traded for a skip, and settled when nothing is left to say", () => {
    const kind = (d: DestinationActivity) => guruAccountOutcomes(post(1, "2026-11-03T17:00:00Z", { destinations: [d] }), NOW)[0]!.kind
    expect(kind(dest("delivered", ["order_linked"], [order("filled")]))).toBe("traded")
    expect(kind(dest("delivered", ["order_linked"], [order("new")]))).toBe("working")
    expect(kind(dest("delivered", ["no_open_lot"]))).toBe("notTraded")
    expect(kind(dest("delivered", ["order_linked"]))).toBe("settled")
  })

  it("joins a second result as 'and 1 more'", () => {
    const d = dest("delivered", ["order_linked", "no_open_lot"], [order("filled")])
    expect(guruAccountOutcomes(post(1, "2026-11-03T17:00:00Z", { instructions: [{ action: "buy", symbol: "PM", price: "100" }, { action: "close", symbol: "X", price: null }], destinations: [d] }), NOW)[0]!.summary).toBe(
      "Bought $100.00 of PM stock and 1 more",
    )
  })
})

describe("buildFeed", () => {
  const traded = post(3, "2026-11-03T17:00:00Z", { destinations: [dest("delivered", ["order_linked"], [order("filled")])] })
  const waiting = post(2, "2026-11-03T14:00:00Z", { decision: "review", destinations: [dest("review_required", [])] })
  const chat = post(1, "2026-11-02T16:00:00Z", { decision: "ignore" })
  const other = post(4, "2026-11-03T18:00:00Z", { guru_id: "a" })
  const day: GuruDayStats = { guru_id: "z", posts: 2, traded: 1, read_seconds: 2, waiting: [waiting] }

  it("lists only the guru's posts, newest first, grouped by day", () => {
    const feed = buildFeed("z", [other, chat, traded], undefined, NOW)
    expect(feed.days.flatMap((d) => d.entries.map((e) => e.post.sequence))).toEqual([3, 1])
    expect(feed.days).toHaveLength(2)
  })

  it("lists the posts the engine holds as waiting even when not loaded, and counts them", () => {
    const feed = buildFeed("z", [traded], day, NOW)
    expect(feed.waitingCount).toBe(1)
    const entries = feed.days.flatMap((d) => d.entries)
    expect(entries.map((e) => e.post.sequence)).toEqual([3, 2])
    expect(entries.find((e) => e.post.sequence === 2)!.isWaiting).toBe(true)
  })

  it("drops a waiting post whose trading day has ended", () => {
    expect(buildFeed("z", [], day, new Date("2026-11-05T15:00:00Z")).waitingCount).toBe(0)
  })

  it("filters entries by what became of them", () => {
    const entries = buildFeed("z", [chat, traded], day, NOW).days.flatMap((d) => d.entries)
    const ids = (filter: Parameters<typeof includesEntry>[0]) => entries.filter((e) => includesEntry(filter, e)).map((e) => e.post.sequence)
    expect(ids("traded")).toEqual([3])
    expect(ids("waiting")).toEqual([2])
    expect(ids("notTraded")).toEqual([1])
    expect(ids("all")).toHaveLength(3)
  })
})

describe("guruStats", () => {
  it("shows no counts before the day is read, never a zero it has not counted", () => {
    expect(guruStats(undefined, 0, false)).toEqual({ postsToday: null, tradedToday: null, waiting: 0, averageRead: null })
    expect(guruStats(undefined, 0, true)).toMatchObject({ postsToday: 0, tradedToday: 0 })
  })
})

describe("guruHoldings", () => {
  const lot = (guru: string | null, qty: string, avg: string, pl: string) => ({ lot_id: "l", guru_id: guru, posted_at: null, remaining_qty: qty, average_price: avg, unrealized_pl: pl })
  const account = (id: string): AccountOverview =>
    ({
      account_id: id,
      positions: [
        { symbol: "A", lots: [lot("z", "2", "10", "5"), lot("a", "1", "10", "1")] },
        { symbol: "B", lots: [lot("z", "1", "30", "-2"), lot("z", "0", "99", "9")] },
      ],
    }) as unknown as AccountOverview

  it("totals what a guru's calls cost and how they stand, across the setup's accounts only", () => {
    const holdings = guruHoldings("z", [account("paper-1"), account("removed")], new Set(["paper-1"]))
    expect(holdings).toEqual({ cost: 50, gain: 3, stocks: 2 })
  })

  it("is nothing while nothing from the guru is held", () => {
    expect(guruHoldings("nobody", [account("paper-1")], new Set(["paper-1"]))).toBeNull()
  })
})
