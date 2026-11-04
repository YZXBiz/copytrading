import { describe, expect, it } from "vitest"
import { deadlineText, endOfTradingDay } from "./deadline"

const LA = "America/Los_Angeles"

describe("endOfTradingDay", () => {
  it("is 20:00 New York time on the post's day: 01:00 UTC in winter, 00:00 UTC in summer", () => {
    expect(endOfTradingDay("2026-11-03T17:00:00Z").toISOString()).toBe("2026-11-04T01:00:00.000Z")
    expect(endOfTradingDay("2026-07-01T14:00:00Z").toISOString()).toBe("2026-07-02T00:00:00.000Z")
  })

  it("belongs to the next day for a post from 20:00 New York time on", () => {
    // 20:30 EST on Nov 3.
    expect(endOfTradingDay("2026-11-04T01:30:00Z").toISOString()).toBe("2026-11-05T01:00:00.000Z")
  })
})

describe("deadlineText", () => {
  it("says today, in the owner's zone with its name", () => {
    const deadline = endOfTradingDay("2026-11-03T17:00:00Z")
    expect(deadlineText(deadline, new Date("2026-11-03T21:00:00Z"), LA)).toBe("Deadline today: 5:00 PM PST")
    expect(deadlineText(deadline, new Date("2026-11-03T21:00:00Z"), "America/New_York")).toBe("Deadline today: 8:00 PM EST")
  })

  it("says tomorrow for a post made after 20:00 New York time, not today", () => {
    // Posted 20:30 EST Nov 3 (5:30 PM PST); the deadline is 5:00 PM PST on Nov 4.
    const deadline = endOfTradingDay("2026-11-04T01:30:00Z")
    expect(deadlineText(deadline, new Date("2026-11-04T01:30:00Z"), LA)).toBe("Deadline tomorrow: 5:00 PM PST")
  })

  it("names the weekday further out", () => {
    const deadline = endOfTradingDay("2026-11-03T17:00:00Z")
    expect(deadlineText(deadline, new Date("2026-11-01T12:00:00Z"), LA)).toBe("Deadline on Tue 5:00 PM PST")
  })
})
