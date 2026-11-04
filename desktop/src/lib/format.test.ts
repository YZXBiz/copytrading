import { describe, expect, it } from "vitest"
import { ago, dateTime, money, monthDay, percent, shares, signedMoney, signedPercent, timeOfDay } from "./format"

describe("money", () => {
  it("formats decimal strings with grouping and cents", () => {
    expect(money("2700.08")).toBe("$2,700.08")
    expect(money(722.04)).toBe("$722.04")
    expect(money("0")).toBe("$0.00")
  })
  it("shows a dash for a missing or unreadable value", () => {
    expect(money(null)).toBe("—")
    expect(money(undefined)).toBe("—")
    expect(money("n/a")).toBe("—")
  })
})

describe("signedMoney", () => {
  it("signs gains and losses, and leaves zero bare", () => {
    expect(signedMoney("12")).toBe("+$12.00")
    expect(signedMoney("-15.19")).toBe("−$15.19")
    expect(signedMoney(0)).toBe("$0.00")
    expect(signedMoney(null)).toBe("—")
  })
})

describe("percent", () => {
  it("reads a fraction", () => {
    expect(percent(0.29763)).toBe("29.8%")
    expect(percent("0.5", 0)).toBe("50%")
    expect(percent(null)).toBe("—")
  })
  it("signs it, with no sign on a rounded zero", () => {
    expect(signedPercent("0.46524")).toBe("+46.5%")
    expect(signedPercent(-0.29763)).toBe("−29.8%")
    expect(signedPercent(0.00001)).toBe("0.0%")
  })
})

describe("shares", () => {
  it("keeps up to six decimals and drops trailing zeros", () => {
    expect(shares("6.679793")).toBe("6.679793")
    expect(shares("12.5000")).toBe("12.5")
    expect(shares("1234")).toBe("1,234")
    expect(shares("1.9240678")).toBe("1.924068")
    expect(shares(null)).toBe("—")
  })
})

describe("times", () => {
  const iso = "2026-11-03T18:41:33Z"
  it("formats in the given zone", () => {
    expect(dateTime(iso, { timeZone: "America/New_York" })).toBe("Nov 3, 1:41 PM")
    expect(timeOfDay(iso, { timeZone: "UTC" })).toBe("6:41 PM")
    expect(monthDay(iso, { timeZone: "UTC" })).toBe("Nov 3")
  })
  it("says how long ago", () => {
    const now = new Date("2026-11-03T18:41:40Z")
    expect(ago(iso, now)).toBe("just now")
    expect(ago("2026-11-03T18:30:00Z", now)).toBe("11 min ago")
    expect(ago("2026-11-03T15:00:00Z", now)).toBe("3 h ago")
    expect(ago("2026-11-01T18:00:00Z", now)).toBe("2 d ago")
  })
})
