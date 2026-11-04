import { describe, expect, it } from "vitest"
import { parseDec } from "./decimal"
import { dollars, partOfText, shareCount, sharesOf, sharesText, usd } from "./quantity"

const d = (text: string) => parseDec(text)!

describe("shares", () => {
  it("counts a stock to three decimals and marks a rounded count", () => {
    expect(sharesText(d("2.985"), "PM")).toBe("2.985 shares")
    expect(shareCount(d("2.052463"), "SOXS")).toBe("≈2.052")
    expect(shareCount(d("6.679793"), "SOXL")).toBe("≈6.68")
  })

  it("calls one share one share, even a hundredth off", () => {
    expect(sharesText(d("1"), "F")).toBe("1 share")
    expect(sharesText(d("1.004"), "F")).toBe("≈1 share")
    expect(sharesText(d("2"), "F")).toBe("2 shares")
  })

  it("counts a coin to the billionth and names the coin", () => {
    expect(sharesText(d("0.001231481"), "BTC/USD")).toBe("0.001231481 units of BTC")
    expect(sharesOf(d("0.001231481"), "BTC/USD")).toBe("0.001231481")
    expect(sharesOf(d("3"), "NIO")).toBe("3 shares")
  })

  it("words a part of a lot", () => {
    expect(partOfText(d("0.44"), d("0.885"), "WMT")).toBe("0.44 of 0.885 shares")
    expect(partOfText(d("0.5"), d("1"), "WMT")).toBe("0.5 of 1 share")
  })
})

describe("price", () => {
  it("shows money to the cent and whole dollars plainly", () => {
    expect(usd("40.45")).toBe("$40.45")
    expect(usd(null)).toBe("—")
    expect(dollars("160")).toBe("$160")
    expect(dollars("39.5")).toBe("$39.50")
    expect(dollars("1234")).toBe("$1,234")
    expect(dollars("junk")).toBe("—")
  })
})
