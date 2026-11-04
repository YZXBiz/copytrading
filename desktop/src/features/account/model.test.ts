import { describe, expect, it } from "vitest"
import type { SourceActivity } from "../../../shared/contract"
import { cardOutcome, isOpenCall } from "@/features/activity/outcome"
import { reasonText } from "@/lib/reasons"
import { dayChange, postOutcome } from "./model"

const post = (over: Partial<SourceActivity>): SourceActivity => ({
  sequence: 1,
  source_at: "2026-11-02T21:13:43Z",
  text: "x",
  decision: "trade",
  guru_id: "g",
  instructions: [{ action: "close", symbol: "AEHR", price: "61.5" }],
  destinations: [],
  ...over,
})

const NOW = new Date("2026-11-03T19:00:00Z")
const held = [{ account_id: "a", status: "review_required", instruction_outcomes: [] as string[] }]

const delivered = (...instruction_outcomes: string[]) => [{ account_id: "a", status: "delivered", instruction_outcomes }]

const order = (over: Record<string, unknown>) =>
  ({ client_id: "c1", symbol: "PM", side: "buy", status: "filled", quantity: "1.6", filled_quantity: "1.6", limit_price: "125", average_fill_price: "124.89", budget_usd: "200", ...over }) as never
const withOrder = (over: Record<string, unknown>) =>
  postOutcome(post({ destinations: [{ account_id: "a", status: "done", instruction_outcomes: ["order_linked"], orders: [order(over)] }] }), "a", NOW)

describe("postOutcome says what Activity says", () => {
  it("calls chat Ignored and a review Waiting for you", () => {
    expect(postOutcome(post({ decision: "ignore" }), "a", NOW).label).toBe("Ignored")
    expect(postOutcome(post({ decision: "review", destinations: held, source_at: "2026-11-03T18:00:00Z" }), "a", NOW)).toMatchObject({
      label: "Waiting for you",
      tone: "warning-light",
    })
  })

  it("gives the same title and tone as Activity for every shape of post", () => {
    const shapes = [
      post({ decision: "ignore" }),
      post({ destinations: delivered("no_open_lot") }),
      post({ destinations: delivered("order_linked") }),
      post({ decision: "review", destinations: held, source_at: "2026-11-02T18:00:00Z" }),
      post({ destinations: [{ account_id: "a", status: "done", instruction_outcomes: [], orders: [order({}), order({ client_id: "c2" })] }] }),
      post({ destinations: [{ account_id: "a", status: "done", instruction_outcomes: ["order_linked"], orders: [order({ client_id: "lotsale-1" })] }] }),
    ]
    for (const shape of shapes) expect(postOutcome(shape, "a", NOW).label).toBe(cardOutcome(shape, NOW).title)
  })

  it("says a skipped call by its reason, in the shared reason wording", () => {
    expect(postOutcome(post({ destinations: delivered("no_open_lot") }), "a", NOW)).toMatchObject({
      label: "Skipped",
      read: reasonText("no_open_lot"),
    })
  })

  it("never shows a raw code", () => {
    expect(postOutcome(post({ destinations: delivered("some_new_reason") }), "a", NOW).read).toContain("Some new reason")
  })

  it("says what a filled order did, and calls a failed one failed", () => {
    expect(withOrder({})).toMatchObject({ label: "Traded", tone: "success-light", read: "Bought $199.82 of PM stock" })
    expect(withOrder({ status: "rejected" })).toMatchObject({ label: "Failed", tone: "destructive-light" })
  })

  it("says several orders once", () => {
    const two = postOutcome(post({ destinations: [{ account_id: "a", status: "done", instruction_outcomes: [], orders: [order({}), order({ client_id: "c2" })] }] }), "a", NOW)
    expect(two.read).toMatch(/and 1 more$/)
  })

  it("is empty for an account the post never reached", () => {
    expect(postOutcome(post({ destinations: delivered("no_open_lot") }), "other", NOW).read).toBe("")
  })
})

describe("dayChange", () => {
  it("is a fraction of yesterday's close", () => {
    const account = { balance: { day_change_usd: "-15.19", previous_close_equity: "2715.27" } } as never
    expect(dayChange(account)?.fraction).toBeCloseTo(-0.005594, 5)
  })
})

describe("whether a post waits is Activity's rule", () => {
  const posts = [
    post({ destinations: held, source_at: "2026-11-03T18:00:00Z" }),
    post({ destinations: delivered("approval_required"), source_at: "2026-11-02T21:13:43Z" }),
    post({ destinations: delivered("approved_by_owner") }),
    post({ destinations: held, source_at: "2026-11-02T18:00:00Z" }),
    post({ destinations: [{ ...held[0]!, orders: [{ client_id: "manual-1" } as never] }], source_at: "2026-11-03T18:00:00Z" }),
  ]
  it("shows Waiting for you exactly when isOpenCall says the post is open", () => {
    for (const p of posts) {
      expect(postOutcome(p, "a", NOW).label === "Waiting for you").toBe(isOpenCall(p, NOW))
    }
    expect(isOpenCall(posts[0]!, NOW)).toBe(true)
    expect(isOpenCall(posts[2]!, NOW)).toBe(false)
    expect(isOpenCall(posts[4]!, NOW)).toBe(false)
  })
})
