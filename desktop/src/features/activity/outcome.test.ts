import { describe, expect, it } from "vitest"
import type { DestinationActivity, OrderActivity, SourceActivity } from "../../../shared/contract"
import { cardOutcome, destinationOutcome, isOpenCall, mergePosts, orderOutcome } from "./outcome"

const NOW = new Date("2026-11-03T21:00:00Z")

const order = (o: Partial<OrderActivity>): OrderActivity => ({
  client_id: "sig-1",
  symbol: "PM",
  side: "buy",
  status: "filled",
  quantity: "1.5",
  filled_quantity: "1.5",
  limit_price: "133.2",
  average_fill_price: "133.2",
  broker_id: null,
  created_at: "2026-11-03T17:00:05Z",
  instruction_index: 0,
  budget_usd: "200",
  requested_usd: "200",
  ...o,
})

const dest = (status: string, outcomes: string[], orders: OrderActivity[] = []): DestinationActivity => ({
  account_id: "primary",
  environment: "paper",
  status,
  instruction_outcomes: outcomes,
  orders,
})

const post = (p: Partial<SourceActivity> = {}): SourceActivity => ({
  sequence: 1,
  source_at: "2026-11-03T17:00:00Z",
  text: "BUY PM 133.2",
  decision: "trade",
  guru_id: "g",
  instructions: [{ action: "buy", symbol: "PM", price: "133.2" }],
  destinations: [],
  ...p,
})

describe("orderOutcome", () => {
  it("words a fill dollar first", () => {
    expect(orderOutcome(order({}))).toMatchObject({ title: "Filled", tone: "positive", detail: "Bought $199.80 of PM stock" })
  })

  it("says a cancelled order's planned amount, and a partial fill what filled", () => {
    expect(orderOutcome(order({ status: "canceled", filled_quantity: "0" })).detail).toBe("Order for $200 of PM stock was cancelled")
    expect(orderOutcome(order({ status: "canceled", filled_quantity: "0.5" })).detail).toBe("Bought $66.60 of PM stock, rest cancelled")
  })

  it("names the owner's own entry", () => {
    expect(orderOutcome(order({ client_id: "manual-1" })).detail).toMatch(/^You bought/)
  })

  it("counts further orders", () => {
    expect(orderOutcome(order({}), 3).detail).toMatch(/and 2 more$/)
  })

  it("never shows a raw status code", () => {
    expect(orderOutcome(order({ status: "pending_new", filled_quantity: "0" }))).toMatchObject({ title: "Working", detail: "Buying $200 of PM stock at up to $133.20" })
  })
})

describe("destinationOutcome", () => {
  it("prefers the post's own orders over the owner's sales", () => {
    const d = dest("delivered", ["order_linked"], [order({ client_id: "lotsale-1", side: "sell" }), order({})])
    expect(destinationOutcome(d).title).toBe("Filled")
  })

  it("says why a post waits, in words", () => {
    expect(destinationOutcome(dest("review_required", ["repeats_an_earlier_call"]))).toMatchObject({
      tone: "caution",
      detail: "The post repeats an earlier call of the guru's",
    })
  })
})

describe("cardOutcome", () => {
  it("titles a filled post Traded, and a cut buy Traded smaller", () => {
    expect(cardOutcome(post({ destinations: [dest("delivered", ["order_linked"], [order({})])] }), NOW).title).toBe("Traded")
    const cut = order({ budget_usd: "100", requested_usd: "200", limited_by: "largest_single_buy" })
    const card = cardOutcome(post({ destinations: [dest("delivered", ["order_linked"], [cut])] }), NOW)
    expect(card.title).toBe("Traded smaller")
    expect(card.accounts[0]!.results[0]!.facts).toContainEqual({ label: "The call asked for", value: "$200" })
  })

  it("says Partly traded when one order filled and another did not", () => {
    const d = dest("delivered", ["order_linked", "order_linked"], [order({}), order({ client_id: "sig-2", status: "canceled", filled_quantity: "0" })])
    expect(cardOutcome(post({ destinations: [d] }), NOW).title).toBe("Partly traded")
  })

  it("explains a timed-out buy with the numbers that decided it", () => {
    const timedOut = order({
      status: "canceled",
      filled_quantity: "0",
      cancel_reason: "timeout",
      quote_ask: "134.1",
      submitted_at: "2026-11-03T17:00:05Z",
      ended_at: "2026-11-03T17:01:05Z",
    })
    const result = cardOutcome(post({ destinations: [dest("delivered", ["order_linked"], [timedOut])] }), NOW).accounts[0]!.results[0]!
    expect(result.headline).toBe("Not bought: the price ran above your limit")
    expect(result.facts).toEqual(expect.arrayContaining([{ label: "Your limit", value: "$133.20" }, { label: "Market", value: "$134.10" }, { label: "Waited", value: "60 seconds" }]))
  })

  it("says what Alpaca said when it refused an order", () => {
    const refused = order({ status: "rejected", filled_quantity: "0", reject_reason: "insufficient buying power" })
    const result = cardOutcome(post({ destinations: [dest("delivered", ["order_linked"], [refused])] }), NOW).accounts[0]!.results[0]!
    expect(result.headline).toBe("Not bought: Alpaca rejected it")
    expect(result.facts).toContainEqual({ label: "Alpaca said", value: "insufficient buying power" })
  })

  it("words a skip with its sentence, never its code", () => {
    const sell = post({ instructions: [{ action: "close", symbol: "AEHR", price: "61.5" }], destinations: [dest("delivered", ["no_open_lot"])] })
    const card = cardOutcome(sell, NOW)
    expect(card.title).toBe("Skipped")
    expect(card.accounts[0]!.results[0]).toMatchObject({ headline: "Not sold", note: "No shares bought from this guru are held, so there is nothing to sell" })
  })

  it("says a buy skipped for want of room under a limit, with its numbers", () => {
    const d = { ...dest("delivered", ["total_exposure_cap"]), limits_hit: [{ part: 0, scope: "total" as const, current: "2499.5", proposed: "2500.5", limit: "2500" }] }
    const result = cardOutcome(post({ destinations: [d] }), NOW).accounts[0]!.results[0]!
    expect(result.headline).toBe("Not bought: you're at your total limit")
    expect(result.facts).toContainEqual({ label: "Room left", value: "$0.50" })
  })

  it("waits for the owner until the trading day ends, then says it is too late", () => {
    const review = post({ decision: "review", parser_reason: "price_range", destinations: [dest("review_required", [])] })
    const open = cardOutcome(review, NOW)
    expect(open).toMatchObject({ title: "Waiting for you", tone: "caution" })
    expect(open.accounts[0]).toMatchObject({ waits: true })
    expect(open.accounts[0]!.results[0]).toMatchObject({ headline: "Waiting for you: the guru gave a price range", facts: [{ label: "Copy by", value: expect.stringMatching(/^Deadline (today|tomorrow): \d{1,2}:00 [AP]M /) }] })
    const late = cardOutcome(review, new Date("2026-11-05T15:00:00Z"))
    expect(late.title).toBe("Expired")
    expect(late.accounts[0]!.results[0]!.note).toBe("Too late to copy: its trading day is over.")
  })

  it("asks to approve, not to copy, for an account that approves every order", () => {
    const p = post({ destinations: [dest("delivered", ["approval_required"])] })
    expect(cardOutcome(p, NOW).accounts[0]!.results[0]!.headline).toBe("Waiting for your approval")
  })

  it("titles a chat post Ignored", () => {
    expect(cardOutcome(post({ decision: "ignore", instructions: [] }), NOW).title).toBe("Ignored")
  })
})

describe("isOpenCall", () => {
  const held = post({ decision: "review", destinations: [dest("review_required", [])] })

  it("closes at 20:00 New York time, so a post from 7:59 PM is still open at 7:59 PM", () => {
    // 2026-11-04T00:59Z is 19:59 EST on Nov 3.
    expect(isOpenCall({ ...held, source_at: "2026-11-04T00:59:00Z" }, new Date("2026-11-04T00:59:30Z"))).toBe(true)
    expect(isOpenCall({ ...held, source_at: "2026-11-04T00:59:00Z" }, new Date("2026-11-04T01:00:30Z"))).toBe(false)
  })

  it("counts the trading day in New York whatever the machine's zone", () => {
    // Posted 18:30 ET Nov 3. At 19:30 ET it is already Nov 4 in UTC, but the New York trading day is still Nov 3.
    const at = { ...held, source_at: "2026-11-03T23:30:00Z" }
    expect(isOpenCall(at, new Date("2026-11-04T00:30:00Z"))).toBe(true)
    // At 20:30 ET the trading day is Nov 4, though it is still Nov 3 in Los Angeles.
    expect(isOpenCall(at, new Date("2026-11-04T01:30:00Z"))).toBe(false)
  })

  it("is not open once the owner entered the trade by hand", () => {
    const entered = { ...held, destinations: [dest("review_required", [], [order({ client_id: "manual-9" })])] }
    expect(isOpenCall(entered, NOW)).toBe(false)
  })
})

describe("merging", () => {
  const traded = post({ sequence: 2 })
  const chat = post({ sequence: 1, decision: "ignore" })

  it("replaces a stale copy with the fresh one and keeps newest first", () => {
    const merged = mergePosts([chat, traded], [{ ...chat, text: "edited" }, post({ sequence: 3 })])
    expect(merged.map((p) => p.sequence)).toEqual([3, 2, 1])
    expect(merged[2]!.text).toBe("edited")
  })
})

describe("mergePosts keeps the same array when a refresh brings nothing new", () => {
  it("returns the current array for identical posts, and a new one for a changed post", () => {
    const a = { sequence: 2, source_at: "2026-11-04T14:00:00Z" } as unknown as SourceActivity
    const b = { sequence: 1, source_at: "2026-11-04T13:00:00Z" } as unknown as SourceActivity
    const current = mergePosts([], [a, b])
    expect(mergePosts(current, [{ ...a }, { ...b }])).toBe(current)
    const changed = mergePosts(current, [{ ...a, source_at: "2026-11-04T14:00:01Z" } as SourceActivity])
    expect(changed).not.toBe(current)
    expect(changed[0]?.source_at).toBe("2026-11-04T14:00:01Z")
  })
})
