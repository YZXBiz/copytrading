import { describe, expect, it } from "vitest"
import type { LotSalePreview, LotSaleResult, ManualOrderPlan } from "../../../shared/contract"
import { decText, parseDec } from "./decimal"
import { partAmount, reviewLabel, saleChoices, saleOutcome, saleSentence, sharesLine } from "./lot-sale"

const d = (text: string) => parseDec(text)!

describe("sale amounts", () => {
  it("rounds a part down to hundredths so it never exceeds the lot", () => {
    expect(decText(partAmount(d("2.052463"), d("0.75"), "SOXS"))).toBe("1.53")
    expect(decText(partAmount(d("2.052463"), d("0.5"), "SOXS"))).toBe("1.02")
    expect(decText(partAmount(d("2.052463"), d("1"), "SOXS"))).toBe("2.052463")
  })

  it("keeps a coin to the billionth", () => {
    expect(decText(partAmount(d("0.001231481"), d("0.5"), "BTC/USD"))).toBe("0.00061574")
  })

  it("leaves out a part too small to sell", () => {
    expect(saleChoices(d("0.01"), "F").map((c) => c.title)).toEqual(["All"])
    expect(saleChoices(d("0.885"), "WMT").map((c) => c.title)).toEqual(["¼", "½", "¾", "All"])
  })

  it("never sends a float artifact", () => {
    expect(decText(partAmount(d("0.3"), d("0.5"), "F"))).toBe("0.15")
    expect(decText(partAmount(d("0.7"), d("0.75"), "F"))).toBe("0.52")
  })
})

describe("sharesLine", () => {
  it("says a part, or all of it once", () => {
    expect(sharesLine(d("0.44"), d("0.885"), "WMT")).toBe("0.44 of 0.885 shares")
    expect(sharesLine(d("0.885"), d("0.885"), "WMT")).toBe("All 0.885 shares")
    expect(sharesLine(d("0.0005"), d("0.001231481"), "BTC/USD")).toBe("0.0005 of 0.001231481 units of BTC")
    expect(reviewLabel(d("0.44"), "WMT")).toBe("Sell 0.44 WMT…")
  })
})

const plan = (over: Partial<ManualOrderPlan> = {}): ManualOrderPlan => ({
  side: "sell",
  position_intent: "sell_to_close",
  type: "limit",
  limit_price: "40.45",
  symbol: "SOXS",
  qty: "2.05",
  source_price: "40.45",
  entry_tolerance_pct: "0",
  lot_id: "l1",
  entry_price: "35",
  session: "regular",
  requested_usd: null,
  budget_usd: null,
  limited_by: null,
  ...over,
})
const preview = (fresh_price: string | null) => ({ fresh_price }) as LotSalePreview

describe("saleSentence", () => {
  it("states the limit order and what it comes to at the bid", () => {
    expect(saleSentence(plan(), preview("40.5"))).toBe(
      "Sells 2.05 shares of SOXS with a limit order at $40.45. It fills at that price or better, or not at all. At today's bid of $40.50, that comes to about $83.03.",
    )
  })

  it("leaves out the proceeds without a fresh price, and the limit without one", () => {
    expect(saleSentence(plan(), preview(null))).toMatch(/not at all\.$/)
    expect(saleSentence(plan({ limit_price: null, qty: "1" }), preview(null))).toBe("1 share of SOXS")
  })
})

const result = (over: Partial<LotSaleResult>): LotSaleResult =>
  ({ status: "filled", reason: null, filled_qty: "2.05", filled_avg_price: "40.46", ...over }) as LotSaleResult

describe("saleOutcome", () => {
  it("words each outcome, never a raw code", () => {
    expect(saleOutcome(result({}), "SOXS")).toMatchObject({ title: "Sold 2.05 SOXS at $40.46", tone: "success" })
    expect(saleOutcome(result({ status: "uncertain" }), "SOXS").tone).toBe("warning")
    expect(saleOutcome(result({ status: "rejected", reason: "outside_session" }), "SOXS")).toMatchObject({
      title: "Nothing was sent",
      detail: "The market was closed",
      tone: "destructive",
    })
    expect(saleOutcome(result({ status: "weird_status", reason: null }), "SOXS").title).toBe("Weird status")
  })
})
