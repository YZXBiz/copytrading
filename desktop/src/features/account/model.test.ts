import { describe, expect, it } from "vitest"
import type { SourceActivity } from "../../../shared/contract"
import { isOpenCall } from "@/features/activity/outcome"
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

const delivered = (...instruction_outcomes: string[]) => [
  { account_id: "a", status: "delivered", instruction_outcomes },
]

describe("postOutcome", () => {
  it("calls chat chat and a review a wait", () => {
    expect(postOutcome(post({ decision: "ignore" }), "a", NOW).label).toBe("Chat")
    expect(postOutcome(post({ decision: "review", destinations: held, source_at: "2026-11-03T18:00:00Z" }), "a", NOW)).toMatchObject({
      label: "Waits for you",
      tone: "warning-light",
    })
  })
  it("says a skipped sale in words", () => {
    expect(postOutcome(post({ destinations: delivered("no_open_lot") }), "a", NOW)).toMatchObject({
      label: "Skipped",
      read: "Sell all AEHR at $61.50 · No AEHR bought for this guru",
    })
  })
  it("never shows a raw code", () => {
    expect(postOutcome(post({ destinations: delivered("some_new_reason") }), "a", NOW).read).toContain("Some new reason")
  })
  it("does not call an order Copied before it filled", () => {
    expect(postOutcome(post({ destinations: delivered("order_linked") }), "a", NOW).label).toBe("Order placed")
  })
})

describe("what an order did", () => {
  const order = (over: Record<string, unknown>) =>
    ({ client_id: "c1", symbol: "PM", side: "buy", status: "filled", quantity: "1.6", filled_quantity: "1.6", limit_price: "125", average_fill_price: "124.89", budget_usd: "200", ...over }) as never
  const withOrder = (over: Record<string, unknown>) =>
    postOutcome(post({ destinations: [{ account_id: "a", status: "done", instruction_outcomes: ["order_linked"], orders: [order(over)] }] }), "a", NOW)

  // The order wording is Activity's `orderOutcome` (tested there); the feed only maps it onto its labels.
  it("calls an order Copied only once it filled", () => {
    expect(withOrder({})).toEqual({ label: "Copied", tone: "success-light", read: "Bought $199.82 of PM stock" })
    expect(withOrder({ client_id: "manual-1" }).read).toMatch(/^You bought/)
  })

  it("says a cancelled, expired or released order was cancelled, never Copied", () => {
    for (const status of ["canceled", "expired", "done_for_day", "replaced", "released_unsubmitted", "aborted_before_submit"]) {
      expect(withOrder({ status, filled_quantity: "0", average_fill_price: null })).toMatchObject({ label: "Cancelled", tone: "outline", read: "Order for $200 of PM stock was cancelled" })
    }
  })

  it("says a rejected order failed, an unconfirmed one needs review, and an open one is working", () => {
    expect(withOrder({ status: "rejected" })).toMatchObject({ label: "Failed", tone: "destructive-light" })
    expect(withOrder({ status: "uncertain" }).label).toBe("Needs review")
    expect(withOrder({ status: "new", filled_quantity: "0" }).label).toBe("Working")
    expect(withOrder({ status: "partially_filled" }).label).toBe("Partly filled")
  })

  it("says several orders once", () => {
    const two = postOutcome(post({ destinations: [{ account_id: "a", status: "done", instruction_outcomes: [], orders: [order({}), order({ client_id: "c2" })] }] }), "a", NOW)
    expect(two.read).toMatch(/and 1 more$/)
  })

  it("leaves out a lot the owner sold by hand", () => {
    const sold = postOutcome(post({ destinations: [{ account_id: "a", status: "done", instruction_outcomes: ["order_linked"], orders: [order({ client_id: "lotsale-1" })] }] }), "a", NOW)
    expect(sold.label).toBe("Order placed")
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
  it("shows Waits for you exactly when isOpenCall says the post is open", () => {
    for (const p of posts) {
      expect(postOutcome(p, "a", NOW).label === "Waits for you").toBe(isOpenCall(p, NOW))
    }
    expect(isOpenCall(posts[0]!, NOW)).toBe(true)
    expect(isOpenCall(posts[2]!, NOW)).toBe(false)
    expect(isOpenCall(posts[4]!, NOW)).toBe(false)
  })
  it("says a review whose day ended was not copied", () => {
    const old = post({ decision: "review", destinations: held, source_at: "2026-11-02T18:00:00Z" })
    expect(postOutcome(old, "a", NOW).label).toBe("Not copied")
  })
})
