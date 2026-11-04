import { describe, expect, it } from "vitest"
import { codeWords, reasonText, refusalLine, refusalOutcome, refusalReason, sentence } from "./reasons"

describe("reason words", () => {
  it("knows its sentences and falls back to words, never snake_case", () => {
    expect(reasonText("daily_entry_cap")).toBe("Your daily entry limit was reached")
    expect(reasonText("some_new_code")).toBe("Some new code")
    expect(reasonText(null)).toBe("—")
    expect(codeWords(null)).toBe("—")
    expect(codeWords("no_open_lot")).toBe("No open lot")
    expect(sentence("the buy was not made")).toBe("The buy was not made.")
  })

  it("words one code the same on every screen that has no by-hand advice", () => {
    expect(reasonText("source_unavailable")).toBe("Discord could not be reached")
    expect(reasonText("no_open_lot")).toBe("No shares bought from this guru are held, so there is nothing to sell")
  })
})

describe("refusals", () => {
  it("say why and what to do for a by-hand order, else use the shared wording", () => {
    expect(refusalReason("preview_expired")).toBe("The check expired before you confirmed. Review again.")
    expect(refusalReason("daily_entry_cap")).toBe("Your daily entry limit was reached. Raise it in Connections or wait.")
    expect(refusalReason("source_unavailable")).toBe("Discord could not be reached")
    expect(refusalLine("not_sent")).toBe("It wasn't sent: things changed just before. Review again.")
    expect(refusalLine("Alpaca said no")).toBe("Alpaca said no")
  })

  it("explains what became of an order that did not go well", () => {
    expect(refusalOutcome({ status: "rejected", reason: null } as never)).toBe("It wasn't sent: things changed just before. Review again.")
    expect(refusalOutcome({ status: "uncertain", reason: "x" } as never)).toBe("Alpaca didn't confirm this order. Check the account's orders first.")
    expect(refusalOutcome({ status: "filled", reason: null } as never)).toBeNull()
  })
})
