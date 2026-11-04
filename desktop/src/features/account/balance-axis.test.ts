import { describe, expect, it } from "vitest"
import { balanceAxis } from "./balance-axis"

describe("balanceAxis", () => {
  it("rounds a month of a $2,700 account to hundreds, with room for the high and low labels", () => {
    const axis = balanceAxis([3068.26, 2900, 2715.27])
    expect(axis.ticks).toEqual([2600, 2700, 2800, 2900, 3000, 3100, 3200])
    expect(axis.domain).toEqual([2600, 3200])
    expect(axis.digits).toBe(0)
  })

  it("keeps every value inside the domain and at most six intervals, at any scale", () => {
    for (const values of [[100_000, 100_020], [2700, 2700.4], [250_000, 310_000], [0.5, 3], [99.9, 100.1]]) {
      const { domain, ticks } = balanceAxis(values)
      expect(domain[0]).toBeLessThan(Math.min(...values))
      expect(domain[1]).toBeGreaterThan(Math.max(...values))
      expect(ticks.length).toBeLessThanOrEqual(7)
      expect(ticks[0]).toBe(domain[0])
      expect(ticks.at(-1)).toBe(domain[1])
    }
  })

  it("shows cents only when a step is under a dollar", () => {
    expect(balanceAxis([0.5, 0.9]).digits).toBe(2)
    expect(balanceAxis([2700, 2790]).digits).toBe(0)
  })

  it("draws a flat balance as a short axis around it", () => {
    const { domain, ticks } = balanceAxis([1000, 1000, 1000])
    expect(domain[0]).toBeLessThan(1000)
    expect(domain[1]).toBeGreaterThan(1000)
    expect(ticks.length).toBeGreaterThanOrEqual(2)
  })
})
