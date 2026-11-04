import { describe, expect, it } from "vitest"
import type { AccountOverview } from "../../../shared/contract"
import { sortPositions } from "./positions-sort"

type Position = AccountOverview["positions"][number]

const position = (symbol: string, market_value: string, unrealized_plpc: string) => ({ symbol, market_value, unrealized_plpc }) as Position

const held = [position("SOXL", "438.46", "-0.298"), position("AEHR", "1200", "0.12"), position("SOXS", "91.52", "0.465")]

describe("sortPositions", () => {
  it("puts the biggest value first, the best gain first, and stocks A to Z", () => {
    expect(sortPositions(held, "value").map((p) => p.symbol)).toEqual(["AEHR", "SOXL", "SOXS"])
    expect(sortPositions(held, "gain").map((p) => p.symbol)).toEqual(["SOXS", "AEHR", "SOXL"])
    expect(sortPositions(held, "stock").map((p) => p.symbol)).toEqual(["AEHR", "SOXL", "SOXS"])
  })

  it("leaves the account's own order alone", () => {
    sortPositions(held, "stock")
    expect(held.map((p) => p.symbol)).toEqual(["SOXL", "AEHR", "SOXS"])
  })
})
