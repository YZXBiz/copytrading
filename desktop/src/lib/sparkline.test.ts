import { describe, expect, it } from "vitest"
import { sparkPath } from "./sparkline"

describe("sparkPath", () => {
  it("draws nothing for fewer than two values", () => {
    expect(sparkPath([], 100, 40)).toBe("")
    expect(sparkPath([3], 100, 40)).toBe("")
  })
  it("puts the high value at the top and the low at the bottom, inside the padding", () => {
    expect(sparkPath([0, 10], 100, 40, 4)).toBe("M0,36 L100,4")
  })
  it("runs flat data through the middle", () => expect(sparkPath([2, 2, 2], 100, 40)).toBe("M0,20 L50,20 L100,20"))
  it("runs a flat zero along the bottom, so no count reads as a value", () => expect(sparkPath([0, 0], 100, 40, 3)).toBe("M0,37 L100,37"))
})
