import { describe, expect, it } from "vitest"
import { metaSegments } from "./meta"

describe("metaSegments", () => {
  it("splits an engine string at its dots", () => {
    expect(metaSegments("Nov 3, 10:39 AM · Needs your review")).toEqual(["Nov 3, 10:39 AM", "Needs your review"])
  })

  it("keeps a string without a dot whole, and drops an empty one", () => {
    expect(metaSegments("Buy SOXL at $89.37")).toEqual(["Buy SOXL at $89.37"])
    expect(metaSegments("")).toEqual([])
  })

  it("does not split a dot inside a word", () => {
    expect(metaSegments("Tom·Jerry")).toEqual(["Tom·Jerry"])
  })
})
