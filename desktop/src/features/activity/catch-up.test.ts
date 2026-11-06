import { describe, expect, it } from "vitest"
import type { SourceActivity } from "../../../shared/contract"
import { catchUp } from "./catch-up"

const NOW = new Date("2026-11-04T19:00:00Z")
const SINCE = new Date("2026-11-04T14:00:00Z")
const post = (sequence: number, over: Partial<SourceActivity>): SourceActivity =>
  ({ sequence, source_at: "2026-11-04T15:00:00Z", text: "x", decision: "trade", guru_id: "g", instructions: [{ action: "buy", symbol: "SOXL", price: "89" }], destinations: [], ...over }) as SourceActivity
const order = (client_id: string, status: string, over: object = {}) => ({ client_id, symbol: "SOXL", side: "buy", status, quantity: "1", filled_quantity: status === "filled" ? "1" : "0", limit_price: "89", average_fill_price: "88.5", budget_usd: "100", broker_id: null, created_at: "2026-11-04T15:00:05Z", instruction_index: 0, ...over })
const dest = (account_id: string, over: object = {}) => ({ account_id, status: "delivered", instruction_outcomes: ["order_linked"], ...over }) as never
const name = () => "Zhao"

const filled = post(1, { destinations: [dest("a", { orders: [order("c1", "filled")] })] })
const working = post(2, { source_at: "2026-11-04T15:10:00Z", destinations: [dest("a", { orders: [order("c2", "accepted")] })] })
const held = post(3, { source_at: "2026-11-04T15:20:00Z", decision: "review", destinations: [dest("a", { status: "review_required", instruction_outcomes: [] })] })
const refused = post(4, { source_at: "2026-11-04T15:30:00Z", destinations: [dest("b", { instruction_outcomes: ["price_not_given"] })] })
const chat = post(5, { decision: "ignore" })
const old = post(6, { source_at: "2026-11-04T13:00:00Z", destinations: [dest("a", { orders: [order("c6", "filled")] })] })

describe("catchUp", () => {
  it("sorts what came in since into waiting, copied and skipped, with the amounts the post shows", () => {
    const digest = catchUp([refused, held, working, filled, chat, old], SINCE, NOW, name)!
    expect(digest.items.map((i) => [i.section, i.text])).toEqual([
      ["skipped", "Buy SOXL at $89. The post gave no price"],
      ["needs-you", "Buy SOXL at $89"],
      ["copied", "Buying $100 of SOXL stock at up to $89.00"],
      ["copied", "Bought $88.50 of SOXL stock"],
    ])
  })

  it("counts them in the line under the title and says since when", () => {
    const digest = catchUp([refused, held, working, filled], SINCE, NOW, name)!
    expect(digest.summary).toMatch(/^2 copied, 1 filled, 1 waiting for you, 1 skipped since /)
  })

  it("is null when nothing new came in, and keeps one account's posts for its page", () => {
    expect(catchUp([old, chat], SINCE, NOW, name)).toBeNull()
    expect(catchUp([filled, refused], SINCE, NOW, name, "b")!.items.map((i) => i.section)).toEqual(["skipped"])
    expect(catchUp([filled], SINCE, NOW, name, "other")).toBeNull()
  })
})
