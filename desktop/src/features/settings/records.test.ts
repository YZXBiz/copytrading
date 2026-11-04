import { describe, expect, it } from "vitest"
import type { AccountOverview } from "../../../shared/contract"
import { earlierAccounts, recordSummary } from "./records"

const account = (id: string, over: Partial<AccountOverview> = {}): AccountOverview => ({
  account_id: id, environment: "paper", entry_permission: "enabled", total_exposure_usd: null, positions: [], pending_orders: null, balance: null,
  broker_identity: "PA3X0f11", ...over,
})

describe("earlierAccounts", () => {
  it("keeps only the records the saved setup does not name", () => {
    const all = [account("a"), account("b"), account("c")]
    expect(earlierAccounts(all, ["a", "c"]).map((x) => x.account_id)).toEqual(["b"])
    expect(earlierAccounts(all, []).length).toBe(3)
  })
})

describe("recordSummary", () => {
  const lot = { lot_id: "l", guru_id: null, posted_at: null, remaining_qty: "1" }
  const position = (lots: number) => ({ symbol: "F", owned_qty: "1", lots: Array(lots).fill(lot), avg_entry_price: null, current_price: null, market_value: null, unrealized_pl: null, unrealized_plpc: null })

  it("says which Alpaca account, and what is still held", () => {
    expect(recordSummary(account("a"))).toBe("Alpaca paper account ending 0f11\nNo copied shares")
    expect(recordSummary(account("a", { environment: "live", positions: [position(1), position(1)] }))).toBe("Alpaca live account ending 0f11\n2 copied buys")
    expect(recordSummary(account("a", { positions: [position(1)] }))).toBe("Alpaca paper account ending 0f11\n1 copied buy")
  })

  it("adds when it was last active, never as a raw timestamp", () => {
    const text = recordSummary(account("a", { last_activity_at: "2026-10-12T18:15:00Z" }))
    expect(text).toMatch(/\nLast active Oct 12, \d{1,2}:15 [AP]M$/)
    expect(text).not.toContain("2026-")
  })
})
