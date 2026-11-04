import { describe, expect, it } from "vitest"
import type { DiagnosticsEntry } from "../../../shared/contract"
import { displayFields, includes, isProblem, outcomeTitle, searchText, title } from "./journal"

const entry = (over: Partial<DiagnosticsEntry>): DiagnosticsEntry => ({
  id: "1", kind: "trading", at: "2026-11-03T14:00:00Z", name: "workflow", outcome: "returned", trace_id: null, workflow_id: null,
  fields: [], payload_json: null, payload_unreadable: false, ...over,
})

describe("title and outcome", () => {
  it("names a ledger event by its event, and says it was recorded", () => {
    const e = entry({ name: "execution.ledger_event", outcome: "submit_error" })
    expect(title(e)).toBe("Order refused")
    expect(outcomeTitle(e)).toBe("Recorded")
  })
  it("names payloads, stages and trading steps, and falls back to plain words", () => {
    expect(title(entry({ kind: "payload", name: "model_response" }))).toBe("Model reply")
    expect(title(entry({ kind: "payload", name: "other" }))).toBe("Captured payload")
    expect(title(entry({ kind: "stage", name: "parsed" }))).toBe("Self-test read")
    expect(title(entry({ name: "model.parse" }))).toBe("Interpretation")
    expect(title(entry({ name: "brand.new" }))).toBe("Trading step")
    expect(outcomeTitle(entry({ outcome: "raised" }))).toBe("Failed")
    expect(outcomeTitle(entry({ outcome: "half_done" }))).toBe("Half done")
  })
})

describe("filters", () => {
  const failed = entry({ outcome: "raised" })
  const capture = entry({ kind: "payload", name: "source_event", outcome: "complete" })
  it("keeps captures, trading steps and problems apart", () => {
    expect(isProblem(failed)).toBe(true)
    expect(includes("problems", failed)).toBe(true)
    expect(includes("problems", capture)).toBe(false)
    expect(includes("captures", capture)).toBe(true)
    expect(includes("trading", capture)).toBe(false)
    expect(includes("all", capture)).toBe(true)
  })
  it("searches the payload and every field, case-insensitively", () => {
    const e = entry({ fields: [{ name: "symbol", value: "SOXS" }], payload_json: '{"Text": "Buy NVDA"}' })
    expect(searchText(e)).toContain("soxs")
    expect(searchText(e)).toContain("buy nvda")
  })
})

describe("displayFields", () => {
  it("words the fields and drops the internal ones", () => {
    const fields = [
      { name: "limit_price", value: "12.3" },
      { name: "payload_bytes", value: "2048" },
      { name: "provider", value: "other" },
      { name: "qty", value: "2.052463" },
      { name: "reason", value: "price_too_high" },
      { name: "side", value: "sell" },
      { name: "symbol", value: "SOXS" },
      { name: "secret_flag", value: "x" },
    ]
    expect(displayFields(entry({ fields }))).toEqual([
      { label: "Stock", value: "Sell SOXS" },
      { label: "Shares", value: "2.052463" },
      { label: "Limit price", value: "$12.30" },
      { label: "Reason", value: "Price too high" },
      { label: "Payload size", value: "2 KB" },
    ])
  })
  it("keeps a value it cannot read as it was written", () => {
    expect(displayFields(entry({ fields: [{ name: "qty", value: "lots" }] }))).toEqual([{ label: "Shares", value: "lots" }])
  })
})
