import { describe, expect, it } from "vitest"
import type { AccountOverview, EngineState, SourceActivity, TradingStatus } from "../shared/contract"
import { type Reading, lastTrade, title, tone, view, waiting } from "../electron/main/menubar/words"
import { drawMark } from "../electron/main/menubar/mark"

const running: EngineState = { state: "running" }
const status = (state: TradingStatus["state"]) => ({ state }) as TradingStatus
const account = (equity: string, change: string, close: string) =>
  ({ account_id: "a", balance: { equity, day_change_usd: change, previous_close_equity: close } }) as AccountOverview
const NOW = new Date("2026-11-03T19:00:00Z")
const order = (over = {}) => ({ client_id: "o1", symbol: "SOXL", side: "buy", status: "filled", filled_quantity: "2", average_fill_price: "49.97", ended_at: "2026-11-03T14:20:00Z", submitted_at: "2026-11-03T14:19:00Z", ...over })
const post = (orders: object[], over: Partial<SourceActivity> = {}) =>
  ({ sequence: 1, source_at: "2026-11-03T14:00:00Z", text: "", decision: "trade", guru_id: "g", instructions: [], destinations: [{ account_id: "a", status: "sent", instruction_outcomes: [], orders }], ...over }) as unknown as SourceActivity
const waitingPost = (sequence: number) =>
  post([], { sequence, decision: "review", instructions: [{ action: "buy", symbol: "F", price: "10" }], destinations: [{ account_id: "zhap", status: "review_required", instruction_outcomes: [] }] } as never)
const reading = (over: Partial<Reading> = {}): Reading => ({ engine: running, status: status("running"), accounts: [account("2681.4", "-11.2", "2692.6")], posts: [], skipped: new Set(), now: NOW, ...over })

describe("the dot", () => {
  it("says what the sidebar footer says, and a stopped engine is red", () => {
    expect(tone(reading())).toBe("success")
    expect(tone(reading({ status: status("degraded") }))).toBe("warning")
    expect(tone(reading({ status: status("paused") }))).toBe("idle")
    expect(tone(reading({ status: status("failed") }))).toBe("destructive")
    expect(tone(reading({ engine: { state: "stopped", reason: "x" } }))).toBe("destructive")
    expect(tone(reading({ status: null }))).toBe("idle")
  })
})

describe("the title", () => {
  it("is the balance and today's change, with a triangle for the direction", () => {
    expect(title([account("2681.4", "-11.2", "2692.6")])).toBe("$2,681 ▼0.4%")
    expect(title([account("2700", "13.5", "2686.5")])).toBe("$2,700 ▲0.5%")
    expect(title([account("100", "0", "100")])).toBe("$100 0.0%")
  })
  it("adds the accounts up, and is empty before any balance is known", () => {
    expect(title([account("1000", "10", "990"), account("2000", "-10", "2010")])).toBe("$3,000 0.0%")
    expect(title([{ account_id: "x", balance: null } as AccountOverview])).toBe("")
  })
})

describe("the last trade", () => {
  it("is the newest copied fill, in words", () => {
    expect(lastTrade([post([order()])])).toMatch(/^Bought \$99\.94 of SOXL, \d{1,2}:\d{2} [AP]M$/)
    expect(lastTrade([post([order({ side: "sell", ended_at: "2026-11-03T15:00:00Z" }), order({ client_id: "o2" })])])).toMatch(/^Sold /)
  })
  it("skips unfilled orders and the owner's own sales", () => {
    expect(lastTrade([post([order({ filled_quantity: "0" }), order({ client_id: "lotsale-1" })])])).toBeNull()
    expect(lastTrade([])).toBeNull()
  })
})

describe("waiting for you", () => {
  it("counts the posts still waiting, never a skipped one, and says nothing until the skips are known", () => {
    const posts = [waitingPost(1), waitingPost(2)]
    expect(waiting({ posts, skipped: new Set(), now: NOW })).toEqual({ count: 2, accountId: "zhap" })
    expect(waiting({ posts, skipped: new Set(["1"]), now: NOW })?.count).toBe(1)
    expect(waiting({ posts, skipped: null, now: NOW })).toBeNull()
  })
})

describe("the menu", () => {
  const labels = (r: Reading) => view(r, "balance").items.flatMap((i) => ("label" in i ? [i.label] : []))
  it("offers Pause while copying, Start while not, and opens the account that waits", () => {
    expect(labels(reading())).toContain("Pause Copying")
    expect(labels(reading({ status: status("paused") }))).toContain("Start Copying")
    const shown = view(reading({ posts: [waitingPost(1)] }), "balance")
    expect(shown.items).toContainEqual({ label: "1 waiting for you", action: "waiting" })
    expect(shown.waitingRoute).toBe("#/accounts/zhap")
  })
  it("cannot start while the engine is down, and shows no title for Dot only", () => {
    const down = reading({ engine: { state: "stopped", reason: "x" }, status: null })
    expect(view(down, "balance").items).toContainEqual({ label: "Start Copying", enabled: false })
    expect(view(reading(), "dot").title).toBe("")
    expect(view(reading(), "balance").title).toBe("$2,681 ▼0.4%")
  })
})

describe("the picture", () => {
  it("draws the whole mark in the state's colour, and nothing else", () => {
    const px = drawMark(36, "success")
    expect(px.length).toBe(36 * 36 * 4)
    const opaque = [...Array(36 * 36).keys()].filter((i) => px[i * 4 + 3] === 255)
    const colours = new Set(opaque.map((i) => `${px[i * 4 + 2]},${px[i * 4 + 1]},${px[i * 4]}`))
    expect(colours).toEqual(new Set(["52,199,89"]))
    expect(px[3]).toBe(0)
  })
})
