import { describe, expect, it } from "vitest"
import { NAV_SCREEN_IDS, parseHash } from "@/features/shell/route"
import { accountOfHash, stockHref } from "./stock-link"

describe("stock link", () => {
  it("names the stock and, when given, the account whose keys and lots the page uses", () => {
    expect(stockHref("soxl")).toBe("#/stock/SOXL")
    expect(stockHref("SOXL", "zhap-account-2")).toBe("#/stock/SOXL?account=zhap-account-2")
    expect(accountOfHash(stockHref("SOXL", "zhap-account-2"))).toBe("zhap-account-2")
    expect(accountOfHash("#/stock/SOXL")).toBeNull()
  })

  it("reads back through the route, a coin's slash included, and stays out of the menus", () => {
    expect(parseHash(stockHref("SOXL", "a"))).toEqual({ screen: "stock", id: "SOXL", sub: null })
    expect(parseHash(stockHref("BTC/USD"))).toEqual({ screen: "stock", id: "BTC/USD", sub: null })
    expect(NAV_SCREEN_IDS).not.toContain("stock")
  })
})
