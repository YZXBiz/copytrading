import { describe, expect, it } from "vitest"
import type { AccountOverview, MarketQuote } from "../../../shared/contract"
import { liveRow, markPrice, tickDirection } from "./live"

type Position = AccountOverview["positions"][number]
const NOW = new Date("2026-11-04T15:00:30Z")
const quote = (over: Partial<MarketQuote> = {}): MarketQuote => ({ feed: "iex", bid: "40.40", ask: "40.50", timestamp: "2026-11-04T15:00:20Z", ...over })
const position = (over: Partial<Position> = {}): Position => ({
  symbol: "F", owned_qty: "10", lots: [], avg_entry_price: "10", current_price: "12", market_value: "120", unrealized_pl: "20", unrealized_plpc: "0.2", ...over,
})

describe("tickDirection", () => {
  it("says up for a higher price and down for a lower one", () => {
    expect(tickDirection(12, 12.01)).toBe("up")
    expect(tickDirection(12, 11.99)).toBe("down")
  })
  it("says nothing for the same price or when either side is missing", () => {
    expect(tickDirection(12, 12)).toBeNull()
    expect(tickDirection(null, 12)).toBeNull()
    expect(tickDirection(12, undefined)).toBeNull()
  })
})

describe("markPrice", () => {
  it("is the middle of a live bid and ask", () => expect(markPrice(quote(), NOW)).toBeCloseTo(40.45))
  it("is the one side when the book has only one", () => expect(markPrice(quote({ bid: null }), NOW)).toBe(40.5))
  it("is nothing for a quote older than two minutes, or none", () => {
    expect(markPrice(quote({ timestamp: "2026-11-04T14:50:00Z" }), NOW)).toBeNull()
    expect(markPrice(null, NOW)).toBeNull()
    expect(markPrice(quote({ bid: "0", ask: null }), NOW)).toBeNull()
  })
})

describe("liveRow", () => {
  it("is the broker's own figures without a live price", () =>
    expect(liveRow(position(), null)).toEqual({ price: 12, value: 120, gain: 20, gainFraction: 0.2 }))
  it("moves the value, and the gain by the same amount, from the live price", () => {
    const row = liveRow(position(), 13.2)
    expect(row.price).toBe(13.2)
    expect(row.value).toBeCloseTo(132)
    expect(row.gain).toBeCloseTo(32)
    expect(row.gainFraction).toBeCloseTo(0.32)
  })
  it("turns a gain into a loss when the live price falls below cost", () => {
    const row = liveRow(position(), 9)
    expect(row.gain).toBeCloseTo(-10)
    expect(row.gainFraction).toBeCloseTo(-0.1)
  })
  it("keeps the broker's figures when it gave no price to scale from", () =>
    expect(liveRow(position({ current_price: null }), 13)).toMatchObject({ price: 13, value: 120, gain: 20 }))
})
