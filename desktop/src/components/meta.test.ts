import { describe, expect, it } from "vitest"
import { metaSegments } from "./meta"

describe("metaSegments", () => {
  it("splits an engine string at its dots and its line breaks", () => {
    expect(metaSegments("Nov 3, 10:39 AM · Needs your review")).toEqual(["Nov 3, 10:39 AM", "Needs your review"])
    expect(metaSegments("Alpaca paper account\nLast active Oct 12")).toEqual(["Alpaca paper account", "Last active Oct 12"])
  })

  it("keeps a string without a dot whole, and drops an empty one", () => {
    expect(metaSegments("Buy SOXL at $89.37")).toEqual(["Buy SOXL at $89.37"])
    expect(metaSegments("")).toEqual([])
  })

  it("does not split a dot inside a word", () => {
    expect(metaSegments("Tom·Jerry")).toEqual(["Tom·Jerry"])
  })
})
