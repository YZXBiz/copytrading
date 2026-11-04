import { describe, expect, it } from "vitest"
import type { SourceActivity } from "../../../shared/contract"
import { dayChange, isWaiting, postOutcome, tradingDay } from "./model"

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
  it("marks a placed order copied", () => {
    expect(postOutcome(post({ destinations: delivered("order_linked") }), "a", NOW).label).toBe("Copied")
  })
})

describe("dayChange", () => {
  it("is a fraction of yesterday's close", () => {
    const account = { balance: { day_change_usd: "-15.19", previous_close_equity: "2715.27" } } as never
    expect(dayChange(account)?.fraction).toBeCloseTo(-0.005594, 5)
  })
})

describe("isWaiting", () => {
  it("waits while an account holds the call and the trading day is open", () => {
    expect(isWaiting(post({ destinations: held, source_at: "2026-11-03T18:00:00Z" }), NOW)).toBe(true)
    expect(isWaiting(post({ destinations: delivered("approval_required") }), new Date("2026-11-02T22:00:00Z"))).toBe(true)
  })
  it("stops waiting once an account approved it or the day ended", () => {
    expect(isWaiting(post({ destinations: delivered("approved_by_owner") }), NOW)).toBe(false)
    expect(isWaiting(post({ destinations: held, source_at: "2026-11-02T18:00:00Z" }), NOW)).toBe(false)
  })
  it("says a review whose day ended was not copied", () => {
    const old = post({ decision: "review", destinations: held, source_at: "2026-11-02T18:00:00Z" })
    expect(postOutcome(old, "a", NOW).label).toBe("Not copied")
  })
})

describe("tradingDay", () => {
  it("rolls to the next day from 20:00 New York", () => {
    expect(tradingDay(new Date("2026-11-03T00:30:00Z"))).toBe("2026-11-02") // 19:30 Nov 2 in New York
    expect(tradingDay(new Date("2026-11-03T01:30:00Z"))).toBe("2026-11-03") // 20:30 Nov 2 in New York
  })
})
