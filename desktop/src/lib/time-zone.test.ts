import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { dateTime } from "./format"
import { NEW_YORK, city, getTimeZone, isZone, setTimeZone, zoneLabel, zoneName } from "./time-zone"

const store = new Map<string, string>()
beforeEach(() => {
  store.clear()
  vi.stubGlobal("localStorage", { getItem: (k: string) => store.get(k) ?? null, setItem: (k: string, v: string) => store.set(k, v), removeItem: (k: string) => store.delete(k) })
})
afterEach(() => vi.unstubAllGlobals())

describe("the saved zone", () => {
  it("is the Mac's own until one is chosen, and again when the choice is cleared", () => {
    expect(getTimeZone()).toBeUndefined()
    setTimeZone("Asia/Tokyo")
    expect(getTimeZone()).toBe("Asia/Tokyo")
    setTimeZone(undefined)
    expect(getTimeZone()).toBeUndefined()
  })

  it("never saves or returns a name that is not a zone", () => {
    setTimeZone("Mars/Olympus")
    expect(getTimeZone()).toBeUndefined()
    store.set("copytrading.timeZone", "Nowhere/Land")
    expect(getTimeZone()).toBeUndefined()
  })

  it("tells listeners when it changes", () => {
    expect(isZone(NEW_YORK)).toBe(true)
    expect(isZone("nope")).toBe(false)
  })

  it("moves every time the app shows", () => {
    const at = "2026-11-03T21:30:00Z"
    setTimeZone("Asia/Tokyo")
    expect(dateTime(at)).toBe("Nov 4, 6:30 AM")
    setTimeZone(NEW_YORK)
    expect(dateTime(at)).toBe("Nov 3, 4:30 PM")
    expect(dateTime(at, { timeZone: "UTC" })).toBe("Nov 3, 9:30 PM")
  })
})

describe("labels", () => {
  const winter = new Date("2026-12-01T12:00:00Z")
  it("names a zone by its city and its long name", () => {
    expect(city("America/Argentina/Buenos_Aires")).toBe("Buenos Aires")
    expect(zoneName("America/Los_Angeles", winter)).toBe("Pacific Standard Time")
    expect(zoneLabel("Asia/Tokyo", winter)).toBe("Tokyo · Japan Standard Time")
  })
  it("calls New York market time, and the default automatic", () => {
    expect(zoneLabel(NEW_YORK, winter)).toBe("New York (market time)")
    expect(zoneLabel(undefined, winter)).toMatch(/^Automatic \(.+\)$/)
  })
})
