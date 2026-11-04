import { describe, expect, it } from "vitest"
import type { AccountOverview, MarketQuote } from "../../../shared/contract"
import { decText } from "./decimal"
import { canQuote, holdings, isLive, livePrice, quoteDetail, quotePrice, quoteProblem } from "./quote"

const NOW = new Date("2026-11-03T16:30:00Z")
const quote = (over: Partial<MarketQuote> = {}): MarketQuote => ({ feed: "iex", bid: "40.10", ask: "40.20", timestamp: "2026-11-03T16:29:00Z", ...over })

describe("quote", () => {
  it("quotes tickers and dollar pairs, nothing else", () => {
    expect(canQuote("SOXS")).toBe(true)
    expect(canQuote("BRK.B")).toBe(true)
    expect(canQuote("BTC/USD")).toBe(true)
    expect(canQuote("")).toBe(false)
    expect(canQuote("soxs")).toBe(false)
    expect(canQuote("1X")).toBe(false)
  })

  it("pays the ask and gets the bid, from the other side when the book has one", () => {
    expect(quotePrice(quote(), false)).toBe("40.20")
    expect(quotePrice(quote(), true)).toBe("40.10")
    expect(quotePrice(quote({ ask: null }), false)).toBe("40.10")
    expect(quotePrice(quote({ bid: "0", ask: null }), true)).toBeNull()
    expect(quotePrice(null, false)).toBeNull()
  })

  it("is live for two minutes", () => {
    expect(isLive(quote(), NOW)).toBe(true)
    expect(isLive(quote({ timestamp: "2026-11-03T16:27:00Z" }), NOW)).toBe(false)
    expect(isLive(quote({ timestamp: null }), NOW)).toBe(false)
    expect(livePrice(quote({ timestamp: "2026-11-03T15:00:00Z" }), false, NOW)).toBeNull()
  })

  it("says when it was quoted, or why there is no price", () => {
    expect(quoteDetail(quote(), false, NOW)).toMatch(/^≈ \$40\.20 at /)
    expect(quoteProblem("F", quote(), false, NOW)).toBeNull()
    expect(quoteProblem("F", null, false, NOW)).toBe("No quote for F")
    expect(quoteProblem("F", quote({ timestamp: "2026-11-03T15:00:00Z" }), false, NOW)).toMatch(/^No live quote for F since /)
    expect(quoteProblem("F", quote({ timestamp: null }), false, NOW)).toBe("No live quote for F")
  })
})

const account = (id: string, ...positions: [string, string, string | null][]): AccountOverview =>
  ({
    account_id: id,
    positions: positions.map(([symbol, owned_qty, current_price]) => ({ symbol, owned_qty, current_price, lots: [] })),
  }) as unknown as AccountOverview

describe("holdings", () => {
  const accounts = [account("a", ["soxs", "2", "40"], ["F", "0", "10"], ["WMT", "1", "100"]), account("b", ["SOXS", "1.5", "41"], ["NIO", "3", null])]

  it("totals what CopyTrading holds by symbol, largest first, leaving out what it does not own", () => {
    expect(holdings(accounts, new Set()).map((h) => [h.symbol, decText(h.shares), h.price])).toEqual([
      ["SOXS", "3.5", "40"],
      ["WMT", "1", "100"],
      ["NIO", "3", null],
    ])
  })

  it("looks only at the chosen accounts", () => {
    expect(holdings(accounts, new Set(["b"])).map((h) => h.symbol)).toEqual(["SOXS", "NIO"])
  })
})
