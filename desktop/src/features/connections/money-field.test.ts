import { describe, expect, it } from "vitest"
import { fromDollars, toCents } from "./money-field"

describe("money field", () => {
  it("turns the draft text into cents and back to the same text", () => {
    for (const text of ["250", "12.5", "0", "1000000"]) expect(fromDollars(toCents(text)! / 100)).toBe(text)
  })
  it("reads an empty or unreadable limit as none, and none as empty text", () => {
    expect(toCents("")).toBeNull()
    expect(toCents("  ")).toBeNull()
    expect(toCents("abc")).toBeNull()
    expect(fromDollars(null)).toBe("")
  })
  it("keeps whole cents exact", () => {
    expect(toCents("0.29")).toBe(29)
    expect(toCents("1234.56")).toBe(123456)
  })
})
