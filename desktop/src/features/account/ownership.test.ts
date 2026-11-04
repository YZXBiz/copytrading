import { describe, expect, it } from "vitest"
import type { OwnershipIncident, Position } from "../../../shared/contract"
import { ownershipFix } from "./ownership"

const incident: OwnershipIncident = {
  incident_id: "inc-1",
  symbol: "NIO",
  expected_qty: "10",
  actual_qty: "38.011",
  observed_at: "2026-11-03T15:00:00Z",
  cause: "x",
}
const position = (broker_qty: string, ...lots: [string, string][]): Position => ({
  symbol: "NIO",
  owned_qty: "0",
  broker_qty,
  lots: lots.map(([lot_id, remaining_qty]) => ({ lot_id, guru_id: null, posted_at: null, remaining_qty })),
  avg_entry_price: null,
  current_price: null,
  market_value: null,
  unrealized_pl: null,
  unrealized_plpc: null,
})

describe("ownershipFix", () => {
  it("counts shares the app did not buy as the owner's", () => {
    const fix = ownershipFix(incident, position("38.011", ["l1", "10"]), "acct")
    expect(fix.headline).toBe("28.011 shares of NIO that CopyTrading didn't buy")
    expect(fix.action).toBe("They're Mine")
    expect(fix.confirm).toBe("Count as Mine")
    expect(fix.request).toEqual({
      resolution_id: "owner-inc-1",
      incident_id: "inc-1",
      account_id: "acct",
      symbol: "NIO",
      actor: "owner",
      reason: "owner_counted_broker_shares",
      broker_qty: "38.011",
      external_qty: "28.011",
      lot_remaining: { l1: "10" },
    })
  })

  it("updates a count that is simply out of date", () => {
    const fix = ownershipFix(incident, position("10", ["l1", "10"]), "acct")
    expect(fix.headline).toBe("CopyTrading's count of NIO is out of date")
    expect(fix.detail).toBe("It counted 10 shares; the broker holds 10 shares. NIO calls wait until you update it.")
    expect(fix.request.external_qty).toBe("0")
  })

  it("counts the oldest copied shares as sold first, with exact decimals", () => {
    const fix = ownershipFix(incident, position("0.3", ["old", "0.1"], ["new", "0.4"]), "acct")
    expect(fix.headline).toBe("Fewer NIO shares at the broker than CopyTrading copied")
    expect(fix.detail).toBe("0.2 shares are missing, likely sold outside CopyTrading. NIO calls wait until you confirm.")
    expect(fix.request).toMatchObject({
      reason: "owner_marked_copied_sold",
      broker_qty: "0.3",
      external_qty: "0",
      lot_remaining: { old: "0", new: "0.3" },
    })
  })

  it("treats a position the broker does not hold as zero", () => {
    expect(ownershipFix(incident, undefined, "acct").request.broker_qty).toBe("0")
  })
})
