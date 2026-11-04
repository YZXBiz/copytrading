import { describe, expect, it } from "vitest"
import { bytes, count, humanCode, joined, restoreBlocker } from "./words"

describe("humanCode", () => {
  it("spaces and capitalises a code, and shows a dash for nothing", () => {
    expect(humanCode("broker_state_mismatch")).toBe("Broker state mismatch")
    expect(humanCode("cooling-down")).toBe("Cooling down")
    expect(humanCode(null)).toBe("—")
    expect(humanCode("")).toBe("—")
  })
})

describe("count and joined", () => {
  it("inflects by number", () => {
    expect(count(1, "file")).toBe("1 file")
    expect(count(1200, "record")).toBe("1,200 records")
    expect(count(0, "copied buy", "copied buys")).toBe("0 copied buys")
  })
  it("lists with commas", () => expect(joined(["a", "b"])).toBe("a, b"))
})

describe("bytes", () => {
  it("uses decimal file sizes", () => {
    expect(bytes(0)).toBe("0 bytes")
    expect(bytes(1)).toBe("1 byte")
    expect(bytes(1500)).toBe("1.5 KB")
    expect(bytes(256_000_000)).toBe("256 MB")
    expect(bytes(3_400_000_000)).toBe("3.4 GB")
  })
})

describe("restoreBlocker", () => {
  it("says what to do about a known refusal and spells out an unknown one", () => {
    expect(restoreBlocker("broker_state_mismatch")).toBe("Alpaca's orders or holdings changed since the backup")
    expect(restoreBlocker("something_new")).toBe("Something new")
  })
})
