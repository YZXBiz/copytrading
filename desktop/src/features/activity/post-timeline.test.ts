import { describe, expect, it } from "vitest"
import type { SourceActivity } from "../../../shared/contract"
import { postTimeline } from "./post-timeline"

const at = (seconds: number) => new Date(Date.parse("2026-11-03T17:20:08Z") + seconds * 1000).toISOString()
const step = (name: string, seconds: number, extra: object = {}) => ({ step: name, at: at(seconds), client_id: null, reason: null, quantity: null, price: null, ...extra })
const order = (extra: object = {}) => ({ client_id: "c1", symbol: "SOXL", side: "buy", status: "filled", quantity: "1", filled_quantity: "1", limit_price: "89", average_fill_price: "89", broker_id: null, created_at: at(5), instruction_index: 0, ...extra })
const post = (timeline: object[], over: Partial<SourceActivity> = {}, orders: object[] = [order()]): SourceActivity =>
  ({
    sequence: 1,
    source_at: at(0),
    text: "SOXL 89 进",
    decision: "trade",
    guru_id: "g",
    instructions: [],
    captured_at: at(0.5),
    read_started_at: at(1),
    read_at: at(4),
    reading: { kind: "trade_made", summary: "Bought SOXL at $89", calls: [] },
    destinations: [{ account_id: "acct", environment: "paper", status: "delivered", instruction_outcomes: [], orders, timeline }],
    ...over,
  }) as unknown as SourceActivity

const fill = [step("received", 4.2), step("sized", 4.4, { client_id: "c1", quantity: "1", price: "89" }), step("sent", 4.6, { client_id: "c1" }), step("accepted", 5, { client_id: "c1" }), step("filled", 6.3, { client_id: "c1", quantity: "1", price: "88.9" })]

describe("postTimeline", () => {
  it("lists the reader, then the account, each step after the one before it", () => {
    const t = postTimeline(post(fill))!
    expect(t.agents.map((a) => a.name)).toEqual(["Reader", "acct"])
    const account = t.spans.filter((s) => s.agentId === "acct")
    expect(account.map((s) => s.label)).toEqual(["Sized the order: 1 share at $89.00", "Sent to Alpaca", "Alpaca accepted the order", "Filled: 1 share at $88.90"])
    expect(account.map((s) => s.kind)).toEqual(["thinking", "tool", "tool", "waiting"])
    for (const [i, s] of account.slice(1).entries()) expect(s.start).toBeGreaterThanOrEqual(account[i]!.end!)
    expect(t.spans.filter((s) => s.agentId === "reader").map((s) => s.label)).toEqual(["Received the post", "Read as: Bought SOXL at $89"])
    expect(t.handoffs).toEqual([expect.objectContaining({ from: "reader", to: "acct" })])
  })

  it("gives every step its own slot however far apart they are, and keeps the real time on the step", () => {
    const hours = [step("received", 4), step("sized", 5, { client_id: "c1", quantity: "1", price: "89" }), step("accepted", 7_200, { client_id: "c1" })]
    const t = postTimeline(post(hours))!
    const [sized, accepted] = t.spans.filter((s) => s.agentId === "acct")
    expect(accepted!.end! - sized!.end!).toBeLessThan(3)
    expect(accepted!.meta).toContain("2 h")
  })

  it("says why a call was skipped, and marks a stop as placed", () => {
    expect(postTimeline(post([step("received", 4), step("skipped", 4.5, { reason: "no_open_lot" })]))!.spans.at(-1)!.label).toBe("Skipped: No shares bought from this guru are held, so there is nothing to sell")
    const stop = postTimeline(post([step("received", 4), step("sized", 5, { client_id: "c1", quantity: "6", price: "44.5" }), step("accepted", 9, { client_id: "c1" })], {}, [order({ order_type: "stop", stop_price: "44.5" })]))!
    expect(stop.spans.map((s) => s.label)).toContain("Stop placed at $44.50")
  })

  it("names a cancel by its cause, not as a failure", () => {
    const t = postTimeline(post([step("received", 4), step("sized", 5, { client_id: "c1", quantity: "1", price: "89" }), step("cancelled", 65, { client_id: "c1" })], {}, [order({ status: "canceled", cancel_reason: "timeout", filled_quantity: "0" })]))!
    const last = t.spans.at(-1)!
    expect(last.label).toBe("Cancelled: not filled in time")
    expect(last.status).toBe("ok")
  })

  it("narrows to one account, and is null when no step is on record", () => {
    expect(postTimeline(post(fill), "other")).toBeNull()
    expect(postTimeline(post([]))).toBeNull()
  })
})
