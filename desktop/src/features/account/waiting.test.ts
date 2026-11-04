import { describe, expect, it } from "vitest"
import type { SourceActivity } from "../../../shared/contract"
import { namedBuyNote } from "@/features/activity/outcome"
import {
  callPhrase,
  gainLine,
  openCall,
  waited,
  waitingCall,
} from "./waiting"

const post = (over: Partial<SourceActivity> = {}): SourceActivity => ({
  sequence: 1,
  source_at: "2026-11-03T15:00:00Z",
  text: "sell soxs 45",
  decision: "review",
  guru_id: "g",
  instructions: [{ action: "close", symbol: "SOXS", price: "45", entry_price: "40" }],
  destinations: [],
  ...over,
})
const dest = (account_id: string, status: string, instruction_outcomes: string[] = []) => ({ account_id, status, instruction_outcomes })
const NOW = new Date("2026-11-03T19:00:00Z") // 2:00 PM in New York

describe("waitingCall", () => {
  it("waits on every account that holds the call, sorted", () => {
    const call = waitingCall(post({ destinations: [dest("b", "review_required"), dest("a", "review_required"), dest("c", "delivered", ["order_linked"])] }))
    expect(call?.accountIds).toEqual(["a", "b"])
    expect(call?.awaitsApproval).toBe(false)
    expect(call?.calls).toHaveLength(1)
  })

  it("is an approval only when every account waits because it asked to approve each order", () => {
    expect(waitingCall(post({ destinations: [dest("a", "delivered", ["approval_required"])] }))?.awaitsApproval).toBe(true)
    expect(waitingCall(post({ destinations: [dest("a", "delivered", ["approval_required"]), dest("b", "review_required")] }))?.awaitsApproval).toBe(false)
    expect(waitingCall(post({ destinations: [dest("a", "delivered", ["named_buy_not_held"])] }))?.awaitsApproval).toBe(false)
  })

  it("places only the parts an account held, or what the reader suggested", () => {
    const two = [
      { action: "buy" as const, symbol: "F", price: "10" },
      { action: "close" as const, symbol: "SOFI", price: "20" },
    ]
    expect(waitingCall(post({ instructions: two, destinations: [dest("a", "delivered", ["order_linked", "approval_required"])] }))?.calls).toEqual([two[1]])
    const suggested = [{ action: "buy" as const, symbol: "NIO", price: null }]
    expect(waitingCall(post({ suggested, destinations: [dest("a", "review_required")] }))?.calls).toEqual(suggested)
  })

  it("does not wait when nothing is held", () => {
    expect(waitingCall(post({ destinations: [dest("a", "delivered", ["order_linked"])] }))).toBeNull()
    expect(waitingCall(post())).toBeNull()
  })
})

describe("openCall", () => {
  const waiting = post({ destinations: [dest("a", "review_required")] })

  it("is open on its trading day", () => {
    expect(openCall(waiting, { skipped: false, now: NOW })).not.toBeNull()
  })

  it("closes when the owner skips it", () => {
    expect(openCall(waiting, { skipped: true, now: NOW })).toBeNull()
  })

  it("closes once the trading day ends at 20:00 New York", () => {
    expect(openCall(waiting, { skipped: false, now: new Date("2026-11-04T00:59:00Z") })).not.toBeNull() // 7:59 PM
    expect(openCall(waiting, { skipped: false, now: new Date("2026-11-04T01:00:00Z") })).toBeNull() // 8:00 PM
  })

  it("closes once the owner placed the trade by hand", () => {
    const order = { client_id: "manual-1" } as never
    const entered = post({ destinations: [{ ...dest("a", "review_required"), orders: [order] }] })
    expect(openCall(entered, { skipped: false, now: NOW })).toBeNull()
  })
})

describe("how a call reads", () => {
  it("phrases buys and sells", () => {
    expect(callPhrase({ action: "buy", symbol: "SOXS", price: "40.45" })).toBe("Buy SOXS at $40.45")
    expect(callPhrase({ action: "close", symbol: "AEHR", price: "61.5" })).toBe("Sell all AEHR at $61.50")
    expect(callPhrase({ action: "reduce", symbol: "WMT", price: null, fraction: "0.5" })).toBe("Sell ½ of WMT")
    expect(callPhrase({ action: "reduce", symbol: "WMT", price: null, fraction: "0.1666666666666666666666666666666666666667" })).toBe("Sell ⅙ of WMT")
  })

  it("shows a sell's gain against its buy", () => {
    expect(gainLine({ action: "close", symbol: "X", price: "50", entry_price: "40" })?.line).toBe("+25.0% from $40.00")
    expect(gainLine({ action: "close", symbol: "X", price: "30", entry_price: "40" })?.line).toBe("−25.0% from $40.00")
    expect(gainLine({ action: "buy", symbol: "X", price: "50", entry_price: "40" })).toBeNull()
  })

  it("counts how long a post waited", () => {
    expect(waited("2026-11-03T18:30:00Z", NOW)).toBe("30m")
    expect(waited("2026-11-03T03:40:00Z", NOW)).toBe("15h 20m")
  })
})

describe("namedBuyNote (Activity's wording, shown on the ticket)", () => {
  const sell = (named: object) =>
    post({ instructions: [{ action: "close", symbol: "SOXS", price: "45", entry_price: "83.35" }], destinations: [{ ...dest("a", "delivered", ["named_buy_not_held"]), named_buys: [named] } as never] })

  it("says why the named buy was not made", () => {
    expect(namedBuyNote(sell({ part: 0, posted_at: "2026-10-23T15:00:00Z", outcome: "daily_entry_cap" }))).toBe(
      "The $83.35 buy on Oct 23 wasn't made. Your daily entry limit was reached.",
    )
  })

  it("says a sold or unfilled buy, and one that never arrived", () => {
    expect(namedBuyNote(sell({ part: 0, posted_at: "2026-10-23T15:00:00Z", outcome: "sold" }))).toBe("The $83.35 buy on Oct 23 is already sold.")
    expect(namedBuyNote(sell({ part: 0, posted_at: "2026-10-23T15:00:00Z", outcome: "not_filled" }))).toBe("The $83.35 buy on Oct 23 never filled.")
    expect(namedBuyNote(sell({ part: 0, posted_at: null, outcome: null }))).toBe("The guru's $83.35 buy never reached this account.")
  })

  it("is empty for a post with no held sell", () => {
    expect(namedBuyNote(post())).toBeNull()
  })
})
