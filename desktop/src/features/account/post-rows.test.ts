import { describe, expect, it } from "vitest"
import type { SourceActivity } from "../../../shared/contract"
import { postRows } from "./post-rows"
import { waitingCall } from "./waiting"

const NOW = new Date("2026-11-03T19:00:00Z")
const post = (over: Partial<SourceActivity>): SourceActivity => ({
  sequence: 1,
  source_at: "2026-11-03T15:00:00Z",
  text: "x",
  decision: "trade",
  guru_id: "g",
  instructions: [{ action: "buy", symbol: "SOXS", price: "40.45" }],
  destinations: [],
  ...over,
})
const held = { account_id: "a", status: "review_required", instruction_outcomes: [] as string[] }
const waits = post({ sequence: 3, destinations: [held] as never })
const chat = post({ sequence: 2, decision: "ignore" })
const filled = post({
  sequence: 1,
  destinations: [{ account_id: "a", status: "done", instruction_outcomes: ["order_linked"], orders: [{ client_id: "c", symbol: "SOXS", side: "buy", status: "filled", quantity: "1", filled_quantity: "1", average_fill_price: "40", budget_usd: "40" }] }] as never,
})

describe("postRows", () => {
  const call = waitingCall(waits)!
  const rows = postRows([chat, filled, waits], [call], "a", NOW, () => false)

  it("puts the calls waiting for the owner first, then the rest in order", () => {
    expect(rows.map((r) => r.post.sequence)).toEqual([3, 2, 1])
    expect(rows[0]).toMatchObject({ label: "Waiting", filter: "waiting", meaning: "Buy SOXS at $40.45" })
  })

  it("sorts the rest into Ignored and Traded", () => {
    expect(rows[1]).toMatchObject({ label: "Ignored", filter: "ignored", meaning: "" })
    expect(rows[2]).toMatchObject({ label: "Traded", filter: "traded" })
  })

  it("names a call the owner skipped for what it is", () => {
    const skipped = postRows([waits], [], "a", NOW, () => true)
    expect(skipped[0]).toMatchObject({ label: "Skipped", filter: "ignored", call: null })
  })
})
