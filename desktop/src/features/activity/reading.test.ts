import { describe, expect, it } from "vitest"
import type { PostReading, SourceActivity } from "../../../shared/contract"
import { duration, fraction } from "./amounts"
import { callHeadline, callNote, headline, instructionPhrase, isLabelOnly, readAsLine, readableText, readingText } from "./reading"
import { dayWindow } from "./time"

const post = (p: Partial<SourceActivity> = {}): SourceActivity => ({
  sequence: 1,
  source_at: "2026-11-03T17:00:00Z",
  text: "hello",
  decision: "trade",
  guru_id: "g",
  instructions: [],
  destinations: [],
  ...p,
})

const stock = { ticker: "WMT", words: "wmt" }

describe("amounts", () => {
  it("reads engine fractions and durations", () => {
    expect(fraction("0.1666666666666666666666666667")).toBe("1/6")
    expect(fraction("0.5")).toBe("1/2")
    expect(duration(45)).toBe("45 seconds")
    expect(duration(180)).toBe("3 minutes")
    expect(duration(7500)).toBe("2 h 5 min")
  })
})

describe("reading", () => {
  it("words a call: headline, size, and what it leaves out", () => {
    const buy = { action: "buy", action_words: "buy", stock, price: { kind: "exact", value: "110", words: "110" }, size: { kind: "fraction", value: "0.16666666666666666", words: "1/6" } } as const
    expect(callHeadline(buy)).toEqual({ title: "Buy WMT at $110", detail: "A sixth of a full position" })
    expect(callNote({ ...buy, size: { kind: "not_given" } })).toBe("no size given, so a full position")
    const sell = { action: "sell", action_words: "sell", stock, price: { kind: "at_market", words: "now" }, share: { kind: "fraction", value: "0.5", words: "half" }, sell_from: { kind: "lot", buy_price: "100", words: "100" } } as const
    expect(callHeadline(sell)).toEqual({ title: "Sell half of the WMT bought at $100", detail: "At the market price" })
    expect(callNote(sell)).toBeNull()
  })

  it("says what an instruction asks for", () => {
    expect(instructionPhrase({ action: "buy", symbol: "ABC", price: "12.34" })).toBe("Buy ABC at $12.34")
    expect(instructionPhrase({ action: "reduce", symbol: "ABC", price: "14", fraction: "0.5" })).toBe("Sell half of ABC at $14")
    expect(instructionPhrase({ action: "close", symbol: "ABC", price: null })).toBe("Sell all ABC at the market price")
    expect(headline(post({ instructions: [{ action: "buy", symbol: "A", price: "1" }, { action: "buy", symbol: "B", price: "2" }] }))).toBe("Buy A at $1 and 1 more")
  })

  it("explains a post with no instructions", () => {
    expect(headline(post({ decision: "ignore", reading: { kind: "chatter" } as PostReading }))).toBe("Just chat, nothing to trade")
    expect(headline(post({ decision: "review" }))).toBe("Needs your review")
    expect(headline(post({ decision: null }))).toBe("Reading the message…")
  })

  it("joins each call of a reading for a feed row", () => {
    const reading: PostReading = {
      kind: "trade_made",
      summary: "",
      calls: [{ action: "buy", action_words: "b", stock, price: { kind: "exact", value: "110", words: "110" }, size: { kind: "not_given" } }],
    }
    expect(readAsLine(post({ reading }))).toBe("Buy WMT at $110")
  })

  it("removes mass mentions and keeps line breaks in the full text, and folds them in a list preview", () => {
    const p = post({ text: "@everyone BUY\nPM  133.2 @here " })
    expect(readingText(p)).toBe("BUY\nPM  133.2")
    expect(readableText(p)).toBe("BUY PM 133.2")
  })

  it("treats a relay's name label as no words, so a picture post shows its picture", () => {
    expect(isLabelOnly("赵哥-股票：")).toBe(true)
    expect(isLabelOnly("buy now:")).toBe(false)
    expect(readableText(post({ text: "赵哥-股票：" }))).toBe("")
  })

  it("keeps the captured content when the capture is complete, and the text otherwise", () => {
    const event = { event_type: "m", message_id: null, channel_id: null, author_id: null, timestamp: null, content: "full words", embeds: [], attachments: [], attachments_omitted: 0, payload_bytes: 1 }
    expect(readingText(post({ text: "short", source_event: { ...event, capture_status: "complete" } }))).toBe("full words")
    expect(readingText(post({ text: "short", source_event: { ...event, capture_status: "oversize" } }))).toBe("short")
  })
})

describe("dayWindow", () => {
  it("spans the owner's calendar day around now", () => {
    const { day_start, day_end } = dayWindow(new Date(2026, 10, 3, 15, 30))
    expect(new Date(day_start)).toEqual(new Date(2026, 10, 3))
    expect(new Date(day_end)).toEqual(new Date(2026, 10, 4))
  })
})
