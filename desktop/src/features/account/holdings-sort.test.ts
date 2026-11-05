import { describe, expect, it } from "vitest"
import type { AccountOverview } from "../../../shared/contract"
import { sortHoldings } from "./holdings-sort"

const p = (symbol: string, market_value: string | null, unrealized_plpc: string | null) => ({ symbol, market_value, unrealized_plpc }) as unknown as AccountOverview["positions"][number]
const held = [p("B", "50", "0.10"), p("A", "200", "-0.02"), p("C", null, null), p("D", "50", "0.30")]

describe("sortHoldings", () => {
  it("puts the biggest value first and the unpriced last", () => expect(sortHoldings(held, "value").map((x) => x.symbol)).toEqual(["A", "B", "D", "C"]))
  it("puts the best gain first", () => expect(sortHoldings(held, "gain").map((x) => x.symbol)).toEqual(["D", "B", "A", "C"]))
  it("sorts by name", () => expect(sortHoldings(held, "name").map((x) => x.symbol)).toEqual(["A", "B", "C", "D"]))
  it("leaves the input alone", () => {
    const copy = [...held]
    sortHoldings(held, "name")
    expect(held).toEqual(copy)
  })
})
