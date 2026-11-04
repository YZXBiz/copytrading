import { describe, expect, it } from "vitest"
import { pruneSkipped, readSkipped } from "./skipped-calls"

const DAY = 24 * 3600 * 1000
const NOW = Date.UTC(2026, 10, 3)

describe("skipped calls", () => {
  it("forgets a skip after a week", () => {
    expect(pruneSkipped({ fresh: NOW - DAY, old: NOW - 8 * DAY }, NOW)).toEqual({ fresh: NOW - DAY })
  })

  it("reads what was stored, and starts empty when storage is empty or damaged", () => {
    const storage = (value: string | null) => ({ getItem: () => value })
    expect(readSkipped(storage(JSON.stringify({ a: NOW - DAY })), NOW)).toEqual({ a: NOW - DAY })
    expect(readSkipped(storage(null), NOW)).toEqual({})
    expect(readSkipped(storage("not json"), NOW)).toEqual({})
    expect(readSkipped(storage("[1,2]"), NOW)).toEqual({})
  })
})
