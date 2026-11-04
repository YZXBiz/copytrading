import { describe, expect, it } from "vitest"
import { dayLabel, groupByDay } from "./time"

// Built from local parts so the days hold in any time zone.
const at = (day: number, hour: number) => new Date(2026, 10, day, hour).toISOString()
const NOW = new Date(2026, 10, 3, 21)

describe("groupByDay", () => {
  it("starts a new group each time the day changes, keeping the order given", () => {
    const posts = [at(3, 10), at(3, 9), at(2, 13), at(3, 8)]
    const days = groupByDay(posts, (p) => p, NOW)
    expect(days.map((d) => [d.label, d.items.length])).toEqual([
      ["Today", 2],
      ["Yesterday", 1],
      ["Today", 1],
    ])
  })

  it("is empty for no posts", () => {
    expect(groupByDay([], (p: string) => p, NOW)).toEqual([])
  })

  it("names an older day by its weekday and date", () => {
    expect(dayLabel(at(1, 12), NOW)).toBe("Sunday, Nov 1")
  })
})
