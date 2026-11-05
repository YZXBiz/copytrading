import { describe, expect, it } from "vitest"
import type { SourceActivity } from "../../../shared/contract"
import { activityRows, matches } from "./activity-rows"

const NOW = new Date("2026-11-04T19:00:00Z")
const post: SourceActivity = {
  sequence: 4,
  source_at: "2026-11-04T15:00:00Z",
  text: "Bought F at 11.2",
  decision: "trade",
  guru_id: "g",
  instructions: [{ action: "buy", symbol: "F", price: "11.2" }],
  destinations: [
    { account_id: "paper-1", status: "done", instruction_outcomes: ["price_not_given"] },
    { account_id: "paper-2", status: "done", instruction_outcomes: ["price_not_given"] },
  ] as never,
}

describe("activityRows", () => {
  const [row] = activityRows([post], NOW, () => "Zhao", "paper-2")

  it("works out each column once", () => {
    expect(row).toMatchObject({ bucket: "skipped", guru: "Zhao", symbol: "F", label: "Skipped" })
    expect(row!.meaning).toContain("F")
  })

  it("keeps only the chosen account's result", () => {
    expect(row!.accounts.map((a) => a.accountId)).toEqual(["paper-2"])
    expect(activityRows([post], NOW, () => "Zhao", null)[0]!.accounts).toHaveLength(2)
  })

  it("finds a row by guru, stock or what an account did", () => {
    expect(matches(row!, "zhao")).toBe(true)
    expect(matches(row!, " f ")).toBe(true)
    expect(matches(row!, "paper-2")).toBe(true)
    expect(matches(row!, "tsla")).toBe(false)
    expect(matches(row!, "")).toBe(true)
  })
})
