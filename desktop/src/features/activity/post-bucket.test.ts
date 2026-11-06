import { describe, expect, it } from "vitest"
import type { SourceActivity } from "../../../shared/contract"
import { bucketOf, dayCounts, dayKey, dayRows, guruMix, outcomeFlow, shiftDay, skipReasons } from "./post-bucket"

const NOW = new Date("2026-11-04T19:00:00Z")
const ZONE = "America/New_York"
const post = (over: Partial<SourceActivity>): SourceActivity => ({ sequence: 1, source_at: "2026-11-04T15:00:00Z", text: "x", decision: "trade", guru_id: "g", instructions: [], destinations: [], ...over })
const order = (status: string) => ({ client_id: "c", symbol: "F", side: "buy", status, quantity: "1", filled_quantity: status === "filled" ? "1" : "0", average_fill_price: "10", budget_usd: "10" })
const dest = (over: object) => ({ account_id: "a", status: "done", instruction_outcomes: [] as string[], ...over }) as never

const chat = post({ sequence: 1, decision: "ignore" })
const filled = post({ sequence: 2, destinations: [dest({ instruction_outcomes: ["order_linked"], orders: [order("filled")] })] })
const held = post({ sequence: 3, destinations: [dest({ status: "review_required" })] })
const refused = post({ sequence: 4, destinations: [dest({ instruction_outcomes: ["price_not_given"] })] })
const cancelled = post({ sequence: 5, destinations: [dest({ instruction_outcomes: ["order_linked"], orders: [order("canceled")] })] })
const unread = post({ sequence: 6, decision: null })

describe("bucketOf", () => {
  it("sorts each post into its one word", () => {
    expect([chat, filled, held, refused, cancelled, unread].map((p) => bucketOf(p, NOW))).toEqual(["ignored", "traded", "waiting", "skipped", "skipped", null])
  })

  it("lets a held call expire into skipped once its trading day is over", () => {
    expect(bucketOf(held, new Date("2026-11-06T19:00:00Z"))).toBe("skipped")
  })
})

describe("days", () => {
  it("reads the day in the zone given", () => {
    expect(dayKey(new Date("2026-11-05T02:00:00Z"), ZONE)).toBe("2026-11-04")
    expect(dayKey(new Date("2026-11-05T02:00:00Z"), "UTC")).toBe("2026-11-05")
    expect(shiftDay("2026-11-01", -1)).toBe("2026-10-31")
  })

  it("counts a day by outcome and by hour", () => {
    const counts = dayCounts([chat, filled, held, refused, unread, post({ sequence: 9, source_at: "2026-11-03T15:00:00Z" })], "2026-11-04", ZONE, NOW)
    expect(counts.total).toEqual({ posts: 5, traded: 1, waiting: 1, skipped: 1, ignored: 1 })
    expect(counts.hours.posts[10]).toBe(5)
  })

  it("gives thirty rows ending on the day, empty days included", () => {
    const rows = dayRows([filled, chat, post({ sequence: 9, source_at: "2026-10-01T15:00:00Z", decision: "ignore" })], "2026-11-04", ZONE, NOW)
    expect(rows).toHaveLength(30)
    expect(rows[29]).toMatchObject({ key: "2026-11-04", traded: 1, ignored: 1 })
    expect(rows[0]!.key).toBe("2026-10-06")
    expect(rows.reduce((n, r) => n + r.ignored, 0)).toBe(1)
  })
})

describe("mixes", () => {
  it("counts outcomes per guru, busiest first", () => {
    const mix = guruMix([chat, filled, post({ sequence: 7, guru_id: "h", decision: "ignore" })], NOW, (id) => (id === "g" ? "Zhao" : "Han"))
    expect(mix.map((m) => [m.guru, m.total, m.ignored, m.traded])).toEqual([["Zhao", 2, 1, 1], ["Han", 1, 1, 0]])
  })

  it("names the reasons posts were skipped, most common first", () => {
    const again = post({ sequence: 8, destinations: [dest({ instruction_outcomes: ["price_not_given"] })] })
    expect(skipReasons([refused, again, cancelled], NOW)).toEqual([
      { reason: "The post gave no price", count: 2 },
      { reason: "Not copied", count: 1 },
    ])
  })
})

describe("outcomeFlow", () => {
  it("links every post to the outcome the mix counts it under, and drops outcomes nothing reached", () => {
    const mix = guruMix([chat, filled, held, refused, cancelled], NOW, () => "g")
    const flow = outcomeFlow(mix)
    expect(flow.links).toEqual([
      { source: "posts", target: "traded", value: 1 },
      { source: "posts", target: "waiting", value: 1 },
      { source: "posts", target: "skipped", value: 2 },
      { source: "posts", target: "ignored", value: 1 },
    ])
    expect(flow.links.reduce((n, link) => n + link.value, 0)).toBe(mix.reduce((n, row) => n + row.total, 0))
    expect(outcomeFlow(guruMix([chat], NOW, () => "g")).links.map((link) => link.target)).toEqual(["ignored"])
  })
})
