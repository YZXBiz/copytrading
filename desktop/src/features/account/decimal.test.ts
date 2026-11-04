import { describe, expect, it } from "vitest"
import { decDown, decMul, decRound, decText, parseDec } from "./decimal"

const d = (text: string) => parseDec(text)!

describe("decimal", () => {
  it("reads engine strings and refuses junk", () => {
    expect(decText(d("2.052463"))).toBe("2.052463")
    expect(decText(d("10"))).toBe("10")
    expect(decText(d("-0.5"))).toBe("-0.5")
    expect(parseDec("1e3")).toBeNull()
    expect(parseDec("")).toBeNull()
    expect(parseDec(null)).toBeNull()
  })

  it("never writes a float artifact", () => {
    expect(0.1 + 0.2).not.toBe(0.3)
    expect(decText(d("0.1") + d("0.2"))).toBe("0.3")
    expect(decText(decMul(d("0.885"), d("0.5")))).toBe("0.4425")
  })

  it("rounds a share down so a sale never asks for more than the lot holds", () => {
    expect(decText(decDown(decMul(d("2.052463"), d("0.75")), 2))).toBe("1.53")
    expect(decText(decDown(decMul(d("0.001231481"), d("0.5")), 9))).toBe("0.00061574")
  })

  it("rounds half away from zero for display", () => {
    expect(decText(decRound(d("2.985499"), 3))).toBe("2.985")
    expect(decText(decRound(d("2.9855"), 3))).toBe("2.986")
    expect(decText(decRound(d("-2.9855"), 3))).toBe("-2.986")
  })
})
