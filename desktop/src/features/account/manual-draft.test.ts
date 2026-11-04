import { describe, expect, it } from "vitest"
import type { SourceActivity } from "../../../shared/contract"
import { draftAction, draftFromCall, guessDraft, isValid, newDraft, priceIn, reviewMode, sameShare, share, shareTitle, symbolIn, toInstruction } from "./manual-draft"
import { waitingCall } from "./waiting"

describe("draft to instruction", () => {
  it("copies a buy as the guru's limit price", () => {
    const draft = draftFromCall({ action: "buy", symbol: "soxs", price: "40.45" })
    expect(draft.priceChoice).toBe("guru")
    expect(toInstruction(draft)).toEqual({ action: "buy", symbol: "SOXS", price: "40.45", entry_price: null, fraction: null, usd_amount: null, exit_basis: null })
  })

  it("sells all of a close, and a sell with no price goes at the market", () => {
    const draft = draftFromCall({ action: "close", symbol: "AEHR", price: null, entry_price: "61.5" })
    expect(draft.fraction).toBe("1")
    expect(toInstruction(draft)).toMatchObject({ action: "close", price: null, entry_price: "61.5", fraction: "1" })
  })

  it("a sell of exactly one is a close, however it is written", () => {
    expect(draftAction({ ...newDraft(), isSell: true, fraction: "1.0" })).toBe("close")
    expect(draftAction({ ...newDraft(), isSell: true, fraction: "0.5" })).toBe("reduce")
    expect(draftAction({ ...newDraft(), isSell: true, fraction: "" })).toBe("reduce")
  })

  it("keeps a buy's dollar amount and drops it from a sell", () => {
    expect(toInstruction({ ...newDraft(), symbol: "nflx", price: "10", usdAmount: "200" }).usd_amount).toBe("200")
    expect(toInstruction({ ...newDraft(), isSell: true, symbol: "nflx", fraction: "0.5", usdAmount: "200" }).usd_amount).toBeNull()
  })
})

describe("isValid", () => {
  it("needs a stock and, for a buy, a price", () => {
    expect(isValid(newDraft())).toBe(false)
    expect(isValid({ ...newDraft(), symbol: "F" })).toBe(false)
    expect(isValid({ ...newDraft(), symbol: "F", price: "0" })).toBe(false)
    expect(isValid({ ...newDraft(), symbol: "F", price: "12.5" })).toBe(true)
  })

  it("lets a sell go at the market but needs a share between zero and all", () => {
    expect(isValid({ ...newDraft(), isSell: true, symbol: "F", fraction: "0.5" })).toBe(true)
    expect(isValid({ ...newDraft(), isSell: true, symbol: "F", fraction: "" })).toBe(false)
    expect(isValid({ ...newDraft(), isSell: true, symbol: "F", fraction: "1.5" })).toBe(false)
    expect(isValid({ ...newDraft(), isSell: true, symbol: "F", fraction: "0" })).toBe(false)
  })
})

describe("shares", () => {
  it("compares shares as numbers", () => {
    expect(sameShare("0.5", "0.50")).toBe(true)
    expect(sameShare("0.3333333333333333333333333333333333333333", "0.33333333333333333333333333333333333333339")).toBe(true)
    expect(sameShare("0.5", "0.25")).toBe(false)
  })

  it("names a usual share with a glyph", () => {
    expect(shareTitle("0.1666666666666666666666666666666666666667", false)).toBe("⅙")
    expect(shareTitle("0.75", true)).toBe("¾")
    expect(shareTitle("1", true)).toBe("All")
    expect(shareTitle("1", false)).toBe("Full")
    expect(shareTitle("", false)).toBe("No size")
    expect(shareTitle("0.4", true)).toBe("2/5")
  })
})

describe("guessing a trade from a post", () => {
  it("reads 'sell wmt half' as half of the WMT held", () => {
    const draft = guessDraft("sell wmt half", ["WMT"])!
    expect(draft).toMatchObject({ isSell: true, symbol: "WMT", fraction: "0.5" })
  })

  it("reads a price that is not a share", () => {
    expect(priceIn("wmt 1/6 110")).toBe("110")
    expect(priceIn("sell 50% at $12.5")).toBe("12.5")
    expect(priceIn("no numbers here")).toBeNull()
  })

  it("finds a held stock, a cashtag, or a ticker in capitals", () => {
    expect(symbolIn("sell nio now", ["NIO"])).toBe("NIO")
    expect(symbolIn("adding $nvda", [])).toBe("NVDA")
    expect(symbolIn("Buy SOFI today", [])).toBe("SOFI")
    expect(symbolIn("buy some nvda", [])).toBe("NVDA")
    expect(symbolIn("nothing to see", [])).toBeNull()
  })

  it("sells everything on 'exit', and never sizes a buy as all", () => {
    expect(guessDraft("exit TSLA", ["TSLA"])).toMatchObject({ isSell: true, fraction: "1" })
    expect(guessDraft("buy all F", [])).toMatchObject({ isSell: false, fraction: "" })
  })

  it("reads a post that both buys and sells as a sell only when the stock is held", () => {
    expect(guessDraft("sold F bought SOFI", ["SOFI"])?.isSell).toBe(true)
    expect(guessDraft("sold F bought SOFI", [])?.isSell).toBe(false)
  })

  it("has nothing to say about chat", () => {
    expect(guessDraft("good morning everyone", [])).toBeNull()
    expect(share("a quarter of it")).toBe("0.25")
  })
})

describe("reviewMode", () => {
  const post = (destinations: SourceActivity["destinations"], instructions: SourceActivity["instructions"]) =>
    ({ source_at: "2026-11-03T15:00:00Z", destinations, instructions, suggested: [] }) as unknown as SourceActivity
  const call = { action: "buy" as const, symbol: "F", price: "10" }

  it("enters a trade when there is no call, copies a held one, approves one an account asked to approve", () => {
    expect(reviewMode(null)).toBe("enter")
    expect(reviewMode(waitingCall(post([{ account_id: "a", status: "review_required", instruction_outcomes: [] }], [])))).toBe("enter")
    expect(reviewMode(waitingCall(post([{ account_id: "a", status: "review_required", instruction_outcomes: [] }], [call])))).toBe("copy")
    expect(reviewMode(waitingCall(post([{ account_id: "a", status: "delivered", instruction_outcomes: ["approval_required"] }], [call])))).toBe("approve")
  })
})
