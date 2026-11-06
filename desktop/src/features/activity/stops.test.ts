import { describe, expect, it } from "vitest"
import type { DestinationActivity, OrderActivity, PostReading, SourceActivity } from "../../../shared/contract"
import { guruAccountOutcomes } from "../gurus/model"
import { bucketOf, skipReasons } from "./post-bucket"
import { cardOutcome, orderOutcome } from "./outcome"
import { callHeadline, headline, readAsLine } from "./reading"

const NOW = new Date("2026-11-04T19:00:00Z")
const stock = { ticker: "TQQQ", words: "tqqq" }

const stopOrder = (over: Partial<OrderActivity> = {}): OrderActivity => ({
  client_id: "stp-1",
  symbol: "TQQQ",
  side: "sell",
  status: "accepted",
  quantity: "12.5",
  filled_quantity: "0",
  limit_price: null,
  stop_price: "50.95",
  order_type: "stop",
  average_fill_price: null,
  broker_id: "b-1",
  created_at: "2026-11-04T15:00:05Z",
  instruction_index: 0,
  ...over,
})

const dest = (over: Partial<DestinationActivity>): DestinationActivity => ({ account_id: "a", environment: "paper", status: "done", instruction_outcomes: [], stop_outcomes: [], orders: [], ...over })

const stopPost = (destinations: DestinationActivity[]): SourceActivity => ({
  sequence: 1,
  source_at: "2026-11-04T15:00:00Z",
  text: "剩下一半49.5的tqqq 设置下 跌破50.95出剩下的保护",
  decision: "trade",
  guru_id: "g",
  instructions: [],
  stops: [{ symbol: "TQQQ", stop_price: "50.95", entry_price: "49.5" }],
  destinations,
})

const placed = stopPost([dest({ stop_outcomes: ["order_linked"], orders: [stopOrder()] })])
const filled = stopPost([dest({ stop_outcomes: ["order_linked"], orders: [stopOrder({ status: "filled", filled_quantity: "12.5", average_fill_price: "50.9" })] })])
const off = stopPost([dest({ stop_outcomes: ["follow_stops_off"] })])

describe("a stop post", () => {
  it("reads as the stock and the price, whether or not the account placed it", () => {
    expect(headline(placed)).toBe("Stop TQQQ at $50.95")
    expect(headline(off)).toBe("Stop TQQQ at $50.95")
  })

  it("is named by its call the same way, and says which buy it protects", () => {
    const named = { action: "stop", action_words: "跌破", stock, price: { kind: "exact", value: "50.95", words: "50.95" }, protects: { kind: "lot", buy_price: "49.5", words: "49.5" } } as const
    expect(callHeadline(named)).toEqual({ title: "Stop TQQQ at $50.95", detail: "Sells the TQQQ bought at $49.50 if the price falls to it" })
    expect(callHeadline({ ...named, protects: { kind: "not_said" } }).detail).toBe("Sells every TQQQ share CopyTrading holds if the price falls to it")
    expect(callHeadline({ ...named, protects: { kind: "alongside", call: 0 } }).detail).toBe("Sells the buy in this post if the price falls to it")
    const reading: PostReading = { kind: "trade_made", summary: "A stop", calls: [named] }
    expect(readAsLine({ ...placed, reading })).toBe("Stop TQQQ at $50.95")
  })

  it("counts as traded once its order is placed, and as traded when it fills", () => {
    expect(bucketOf(placed, NOW)).toBe("traded")
    expect(bucketOf(filled, NOW)).toBe("traded")
    expect(cardOutcome(placed, NOW)).toMatchObject({ title: "Traded", tone: "positive" })
    expect(guruAccountOutcomes(placed, NOW)[0]).toMatchObject({ kind: "traded" })
  })

  it("words each state of the order", () => {
    expect(orderOutcome(stopOrder())).toMatchObject({ title: "Stop placed", tone: "positive", detail: "Stop TQQQ at $50.95" })
    expect(orderOutcome(stopOrder({ status: "filled", filled_quantity: "12.5", average_fill_price: "50.9" })).detail).toBe("Stop TQQQ at $50.95 filled")
  })

  it("counts as skipped when the account does not follow stops, with its own reason", () => {
    expect(bucketOf(off, NOW)).toBe("skipped")
    expect(cardOutcome(off, NOW).title).toBe("Skipped")
    expect(cardOutcome(off, NOW).accounts[0]!.results[0]).toMatchObject({ headline: "Stop TQQQ at $50.95 not placed", note: "Following the guru's stops is off" })
    expect(skipReasons([off], NOW)).toEqual([{ reason: "Following the guru's stops is off", count: 1 }])
    expect(guruAccountOutcomes(off, NOW)[0]).toMatchObject({ kind: "notTraded" })
  })

  it("is not held for the owner, so nothing in it is waiting", () => {
    expect(cardOutcome(off, NOW).accounts[0]!.waits).toBe(false)
    expect(bucketOf(off, NOW)).not.toBe("waiting")
  })

  it("does not tell about a stop that ended to make room for a sell or to be placed again", () => {
    const replaced = stopPost([dest({ stop_outcomes: ["order_linked"], orders: [stopOrder({ status: "canceled", cancel_reason: "stop_resized" }), stopOrder({ client_id: "stp-2", quantity: "6" })] })])
    expect(cardOutcome(replaced, NOW)).toMatchObject({ title: "Traded" })
    expect(cardOutcome(replaced, NOW).accounts[0]!.results).toHaveLength(1)
  })
})
