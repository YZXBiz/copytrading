import { describe, expect, it } from "vitest"
import type { ManualOrderPlan, ManualOrderPreview } from "../../../shared/contract"
import { hasSent, isReady, outcomeProblems, previewDetail, previewHeadline, previewProblems, previewStatus, previewWarnings } from "./manual-preview"

const plan = (over: Partial<ManualOrderPlan> = {}): ManualOrderPlan => ({
  side: "buy",
  position_intent: "buy_to_open",
  type: "limit",
  limit_price: "40.45",
  symbol: "SOXS",
  qty: "2.4691",
  source_price: "40.45",
  entry_tolerance_pct: "0",
  lot_id: null,
  entry_price: "40.45",
  session: "regular",
  requested_usd: "100",
  budget_usd: "100",
  limited_by: null,
  ...over,
})
const preview = (over: Partial<ManualOrderPreview> = {}): ManualOrderPreview =>
  ({
    instruction: { action: "buy", symbol: "SOXS", price: "40", entry_price: null, fraction: null, usd_amount: null, exit_basis: null },
    plan: plan(),
    reasons: [],
    checks: [],
    fresh_price: "40.40",
    limit_price: "40.45",
    quote: null,
    source_age_seconds: 130,
    ...over,
  }) as ManualOrderPreview

describe("previewHeadline", () => {
  it("words a buy by the dollars it spends", () => {
    expect(previewHeadline(preview(), "a", 0)).toBe("Buy $100 of SOXS in a")
  })

  it("words a sell by its shares and limit", () => {
    const sell = preview({ plan: plan({ side: "sell", budget_usd: null, qty: "2.05", limit_price: "40.45" }) })
    expect(previewHeadline(sell, "a", 0)).toBe("Sell 2.05 SOXS at $40.45 in a")
  })

  it("names the stock when nothing could be planned", () => {
    expect(previewHeadline(preview({ plan: null }), "a", 0)).toBe("Buy SOXS in a")
    expect(previewHeadline(null, "a", 1)).toBe("a, trade 2")
  })
})

describe("previewDetail", () => {
  it("shows a buy's shares at its limit, the ask, and the post's age", () => {
    expect(previewDetail(preview())).toEqual(["≈2.469 shares at $40.45 or less", "Ask $40.40", "posted 2 min ago"])
  })

  it("quotes the bid for a sell", () => {
    expect(previewDetail(preview({ instruction: { ...preview().instruction, action: "close" }, plan: plan({ budget_usd: null }) }))).toEqual(["Bid $40.40", "posted 2 min ago"])
  })
})

describe("what stops an order", () => {
  it("is ready only with a plan and no reasons", () => {
    expect(isReady(preview())).toBe(true)
    expect(isReady(preview({ reasons: ["outside_session"] }))).toBe(false)
    expect(isReady(preview({ plan: null }))).toBe(false)
    expect(isReady(null)).toBe(false)
  })

  it("says each reason once, in words, with what to do", () => {
    const blocked = preview({ reasons: ["daily_entry_cap"], checks: [{ name: "limits", status: "blocked", reason: "daily_entry_cap" }, { name: "x", status: "blocked", reason: "some_new_code" }] })
    expect(previewProblems(blocked)).toEqual(["Your daily entry limit was reached. Raise it in Connections or wait.", "Some new code"])
  })

  it("explains an ask above the limit with the numbers", () => {
    const warn = preview({ fresh_price: "41", checks: [{ name: "quote", status: "warning", reason: "quote_above_limit" }] })
    expect(previewWarnings(warn)[0]).toBe("The ask is $41.00, above your limit of $40.45: $40.00 plus your 1.13%. It may not fill, and is cancelled if it hasn't in time.")
  })
})

describe("status and outcome", () => {
  it("says ready, can't send, or checking", () => {
    expect(previewStatus(preview(), undefined, false)?.text).toBe("Ready")
    expect(previewStatus(preview({ reasons: ["halted"] }), undefined, false)?.text).toBe("Can't send")
    expect(previewStatus(null, undefined, false)?.text).toBe("Checking")
    expect(previewStatus(null, undefined, true)).toBeNull()
  })

  it("says what became of a sent order, worded", () => {
    const rejected = { result: { status: "rejected", reason: "outside_session" } as never, error: null }
    expect(previewStatus(preview(), rejected, false)).toEqual({ text: "Rejected", tone: "destructive-light" })
    expect(outcomeProblems(rejected)).toEqual(["The market is closed. Review again when it opens."])
    expect(outcomeProblems({ result: null, error: "confirm_failed" })).toEqual(["Couldn't confirm it was placed. Check the account's orders first."])
  })

  it("keeps the call open to review again after a refusal, not after an order that may have gone", () => {
    expect(hasSent([{ result: { status: "rejected" } as never, error: null }])).toBe(false)
    expect(hasSent([{ result: { status: "filled" } as never, error: null }])).toBe(true)
    expect(hasSent([{ result: null, error: "confirm_failed" }])).toBe(true)
    expect(hasSent([{ result: null, error: "invalid_request" }])).toBe(false)
  })
})
