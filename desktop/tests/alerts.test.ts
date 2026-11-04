import { afterEach, describe, expect, it, vi } from "vitest"
import { parseDec } from "@/features/account/decimal"
import { sharesOf as pageSharesOf } from "@/lib/quantity"
import type { AgentProposal, SourceActivity, TradingStatus } from "../shared/contract"
import { AlertMonitor } from "../electron/main/alerts/monitor"
import { CopyingMemory, FillWatch, StoppedWatch, copyingStoppedDue, inTradingHours } from "../electron/main/alerts/watch"
import { type Note, agentRequestNote, fillNotes, sharesOf } from "../electron/main/alerts/words"

afterEach(() => vi.useRealTimers())

const OPENED = new Date("2026-11-03T14:00:00Z")
type Order = Partial<NonNullable<SourceActivity["destinations"][number]["orders"]>[number]>
const order = (over: Order) => ({
  client_id: "o-1", symbol: "GFS", side: "buy", status: "accepted", quantity: "9.804", filled_quantity: "0", limit_price: "51.00", average_fill_price: null,
  broker_id: null, created_at: "2026-11-03T15:00:00Z", instruction_index: 0, submitted_at: "2026-11-03T15:00:00Z", ended_at: null, ...over,
})
const post = (orders: Order[], over: Partial<SourceActivity> = {}, account = "paper") =>
  ({ sequence: 1, source_at: "2026-11-03T14:59:00Z", text: "", decision: "trade", guru_id: "zhao", instructions: [], destinations: [{ account_id: account, status: "sent", instruction_outcomes: [], orders: orders.map(order) }], ...over }) as SourceActivity
const names = (id: string) => (id === "zhao" ? "Zhao" : null)

describe("FillWatch", () => {
  it("says an order that went out once, as sent", () => {
    const watch = new FillWatch(OPENED)
    const posts = [post([{}])]
    expect(watch.news(posts).sent.map((f) => f.clientId)).toEqual(["o-1"])
    expect(watch.news(posts)).toEqual({ sent: [], filled: [] })
  })

  it("says an order that filled once, as filled, and never as sent after", () => {
    const watch = new FillWatch(OPENED)
    expect(watch.news([post([{ status: "filled", filled_quantity: "9.804", average_fill_price: "48.49", ended_at: "2026-11-03T15:01:00Z" }])])).toMatchObject({
      sent: [],
      filled: [{ clientId: "o-1", shares: "9.804", price: "48.49", accountId: "paper", guruId: "zhao", byOwner: false }],
    })
    expect(watch.news([post([{}])])).toEqual({ sent: [], filled: [] })
  })

  it("says an order that went out and filled between two reads only as its fill", () => {
    const watch = new FillWatch(OPENED)
    const news = watch.news([post([{ status: "filled", filled_quantity: "9.804", ended_at: "2026-11-03T15:01:00Z" }])])
    expect(news.sent).toEqual([])
    expect(news.filled).toHaveLength(1)
  })

  it("counts a part-filled order that was then cancelled as a fill of what it bought", () => {
    const watch = new FillWatch(OPENED)
    expect(watch.news([post([{ status: "canceled", filled_quantity: "3", ended_at: "2026-11-03T15:01:00Z" }])]).filled[0]!.shares).toBe("3")
  })

  it("ignores an order cancelled with nothing bought, and one not yet sent", () => {
    const watch = new FillWatch(OPENED)
    expect(watch.news([post([{ status: "canceled" }, { client_id: "o-2", status: "prepared" }])])).toEqual({ sent: [], filled: [] })
  })

  it("never re-announces what happened before the app opened", () => {
    const watch = new FillWatch(OPENED)
    const before = "2026-11-03T13:00:00Z"
    expect(watch.news([post([{ submitted_at: before }, { client_id: "o-2", status: "filled", filled_quantity: "1", ended_at: before }])])).toEqual({ sent: [], filled: [] })
  })

  it("names no guru for the owner's own sale", () => {
    const watch = new FillWatch(OPENED)
    const [fill] = watch.news([post([{ client_id: "lotsale-1", side: "sell" }])]).sent
    expect(fill).toMatchObject({ byOwner: true, guruId: null })
  })
})

describe("StoppedWatch", () => {
  const status = (state: TradingStatus["state"], accounts: [string, string][]): TradingStatus =>
    ({ state, accounts: accounts.map(([id, s]) => ({ id, state: s, error_code: null })) }) as TradingStatus

  it("returns an account that was running and has failed, once", () => {
    const watch = new StoppedWatch()
    expect(watch.stopped(status("running", [["a", "running"], ["b", "running"]]))).toEqual([])
    expect(watch.stopped(status("degraded", [["a", "failed"], ["b", "running"]]))).toEqual(["a"])
    expect(watch.stopped(status("degraded", [["a", "failed"], ["b", "running"]]))).toEqual([])
  })

  it("needs the account to run again before it can stop again", () => {
    const watch = new StoppedWatch()
    watch.stopped(status("running", [["a", "running"]]))
    watch.stopped(status("degraded", [["a", "failed"]]))
    watch.stopped(status("running", [["a", "running"]]))
    expect(watch.stopped(status("degraded", [["a", "failed"]]))).toEqual(["a"])
  })

  it("counts every account that stopped running when the whole run failed", () => {
    const watch = new StoppedWatch()
    watch.stopped(status("running", [["a", "running"], ["b", "running"]]))
    expect(watch.stopped(status("failed", [["b", "paused"], ["a", "paused"]]))).toEqual(["a", "b"])
  })

  it("does not call a pause by the owner a stop", () => {
    const watch = new StoppedWatch()
    watch.stopped(status("running", [["a", "running"]]))
    expect(watch.stopped(status("paused", [["a", "paused"]]))).toEqual([])
  })

  it("forgets what ran when there is no status", () => {
    const watch = new StoppedWatch()
    watch.stopped(status("running", [["a", "running"]]))
    watch.stopped(null as never)
    expect(watch.stopped(status("degraded", [["a", "failed"]]))).toEqual([])
  })
})

describe("CopyingMemory", () => {
  const memory = (on = false) => {
    const saves: boolean[] = []
    return { memory: new CopyingMemory(on, (v) => saves.push(v)), saves }
  }

  it("remembers copying is on from any status that says so, and off only when it is paused", () => {
    const { memory: m, saves } = memory()
    for (const state of ["starting", "running", "degraded"] as const) m.observe(state)
    expect(m.wasOn).toBe(true)
    expect(saves).toEqual([true])
    m.observe("pausing")
    expect(m.wasOn).toBe(false)
    expect(saves).toEqual([true, false])
  })

  it("changes nothing for a failed start or no status, so a crash is remembered as copying", () => {
    const { memory: m, saves } = memory(true)
    m.observe("failed")
    m.observe(null)
    expect(m.wasOn).toBe(true)
    expect(saves).toEqual([])
  })
})

describe("trading hours", () => {
  it("is Monday to Friday, 4:00 AM to 8:00 PM New York time", () => {
    expect(inTradingHours(new Date("2026-11-03T09:00:00Z"))).toBe(true) // Tue 4:00 AM EST
    expect(inTradingHours(new Date("2026-11-03T08:59:00Z"))).toBe(false) // 3:59 AM
    expect(inTradingHours(new Date("2026-11-04T00:59:00Z"))).toBe(true) // 7:59 PM
    expect(inTradingHours(new Date("2026-11-04T01:00:00Z"))).toBe(false) // 8:00 PM
    expect(inTradingHours(new Date("2026-11-07T15:00:00Z"))).toBe(false) // Saturday
    expect(inTradingHours(new Date("2026-10-30T20:00:00Z"))).toBe(true) // Friday 4 PM EDT
  })

  it("says copying is paused at once, then every half hour, but only in trading hours", () => {
    const first = new Date("2026-11-03T15:00:00Z")
    expect(copyingStoppedDue(null, first)).toBe(true)
    expect(copyingStoppedDue(first, new Date("2026-11-03T15:29:00Z"))).toBe(false)
    expect(copyingStoppedDue(first, new Date("2026-11-03T15:30:00Z"))).toBe(true)
    expect(copyingStoppedDue(new Date("2026-11-04T00:00:00Z"), new Date("2026-11-04T03:00:00Z"))).toBe(false) // 10 PM, later 10 PM
  })
})

describe("words", () => {
  it("says shares as the SwiftUI app does", () => {
    expect(sharesOf("9.804", "GFS")).toBe("9.804 shares")
    expect(sharesOf("1", "F")).toBe("1 share")
    expect(sharesOf("1.004", "F")).toBe("≈1 share")
    expect(sharesOf("2.985", "PM")).toBe("2.985 shares")
    expect(sharesOf("2.9854", "PM")).toBe("≈2.985 shares")
    expect(sharesOf("1200", "F")).toBe("1,200 shares")
    expect(sharesOf("0.001231481", "BTC/USD")).toBe("0.001231481")
  })

  // main cannot import src/lib/quantity.ts (it pulls the page's time zone store and React), so this is a second copy: it must not drift.
  it("says shares exactly as the page's own wording does (src/lib/quantity.ts)", () => {
    for (const [value, symbol] of [["9.804", "GFS"], ["1", "F"], ["1.004", "F"], ["0.995", "F"], ["2.9854", "PM"], ["1200.5", "F"], ["0", "F"], ["0.001231481", "BTC/USD"], ["2", "ETH/USD"]] as const) {
      expect(sharesOf(value, symbol)).toBe(pageSharesOf(parseDec(value)!, symbol))
    }
  })

  const fill = (over = {}) => ({ clientId: "o", side: "buy", symbol: "GFS", shares: "9.804", price: "51", accountId: "paper", guruId: "zhao" as string | null, byOwner: false, ...over })

  it("words an order that went out and one that filled", () => {
    const notes = fillNotes({ sent: [fill()], filled: [fill({ price: "48.49", clientId: "p" })] }, names)
    expect(notes.map((n) => [n.title, n.body])).toEqual([
      ["Buying 9.804 shares of GFS at up to $51.00", "From Zhao's post · paper"],
      ["Bought 9.804 shares of GFS at $48.49", "From Zhao's post · paper"],
    ])
    expect(notes.map((n) => n.id)).toEqual(["sent-o", "fill-p"])
  })

  it("marks only a fill, which the open window shows as a toast", () => {
    const notes = fillNotes({ sent: [fill()], filled: [fill({ clientId: "p" })] }, names)
    expect(notes.map((n) => n.fill)).toEqual([undefined, true])
  })

  it("words a sell, a market order, the owner's sale, and an unnamed guru", () => {
    const [sell, market, own, unnamed] = fillNotes(
      { sent: [fill({ side: "sell" }), fill({ price: null }), fill({ byOwner: true, guruId: null }), fill({ guruId: "unknown" })], filled: [] },
      names,
    )
    expect(sell!.title).toBe("Selling 9.804 shares of GFS at $51.00 or more")
    expect(market!.title).toBe("Buying 9.804 shares of GFS")
    expect(own!.body).toBe("Your sale · paper")
    expect(unnamed!.body).toBe("Into paper")
    expect(fillNotes({ sent: [], filled: [fill({ side: "sell", price: null })] }, names)[0]!.title).toBe("Sold 9.804 shares of GFS")
  })

  const proposal = (path: string | null): AgentProposal =>
    ({ proposal_id: "p-1", state: "pending", subject: { kind: "resume_account", account_id: "paper" }, requested_by: { pid: null, path } }) as AgentProposal

  it("announces an agent's request in the words of the approval sheet, and never the assistant's", () => {
    expect(agentRequestNote(proposal("/Users/o/.local/bin/claude"))).toMatchObject({ title: "An agent is asking for approval", body: "Start copying into paper", route: "#/settings/agents" })
    expect(agentRequestNote(proposal(null))).not.toBeNull()
    expect(agentRequestNote(proposal("CopyTrading Assistant"))).toBeNull()
  })
})

describe("AlertMonitor", () => {
  function rig(over: { status?: Partial<TradingStatus>; posts?: SourceActivity[]; proposals?: AgentProposal[]; fills?: boolean; wasOn?: boolean; setup?: boolean; now?: Date } = {}) {
    const notes: Note[] = []
    const state = { status: { state: "running", accounts: [] } as unknown as TradingStatus, posts: over.posts ?? [], proposals: over.proposals ?? [], down: false, fills: over.fills ?? true, now: over.now ?? new Date("2026-11-03T15:00:00Z") }
    Object.assign(state.status, over.status)
    const saves: boolean[] = []
    const monitor = new AlertMonitor({
      request: async (op) => {
        if (state.down) throw new Error("down")
        if (op === "get_trading_status") return { trading: state.status }
        if (op === "get_source_activity") return { activity: { items: state.posts } }
        if (op === "list_proposals") return { proposals: state.proposals }
        throw new Error(op)
      },
      notify: (n) => notes.push(n),
      fillsOn: () => state.fills,
      guruName: names,
      hasSetup: () => over.setup ?? true,
      memory: new CopyingMemory(over.wasOn ?? false, (v) => saves.push(v)),
      now: () => state.now,
    })
    return { monitor, notes, state, saves }
  }

  it("announces a new order once, with the fills switch on", async () => {
    const r = rig({ posts: [post([{ submitted_at: "2026-11-03T15:00:00Z" }])] })
    await r.monitor.tick()
    await r.monitor.tick()
    expect(r.notes.map((n) => n.title)).toEqual(["Buying 9.804 shares of GFS at up to $51.00"])
  })

  it("says nothing of orders with the fills switch off, and does not save them up for when it is turned on", async () => {
    const r = rig({ fills: false, posts: [post([{}])] })
    await r.monitor.tick()
    r.state.fills = true
    await r.monitor.tick()
    expect(r.notes).toEqual([])
  })

  it("announces an agent's request once, when it waits", async () => {
    const waiting = { proposal_id: "p-1", state: "pending", subject: { kind: "start_processing" }, requested_by: { pid: 1, path: "/bin/agent" } } as AgentProposal
    const r = rig({ proposals: [waiting] })
    await r.monitor.tick()
    await r.monitor.tick()
    expect(r.notes.map((n) => n.body)).toEqual(["Start copying"])
  })

  it("announces an account that stopped, even with the fills switch off", async () => {
    const r = rig({ fills: false, status: { accounts: [{ id: "paper", state: "running", error_code: null }] } })
    await r.monitor.tick()
    r.state.status = { state: "degraded", accounts: [{ id: "paper", state: "failed", error_code: "x" }] } as TradingStatus
    await r.monitor.tick()
    expect(r.notes).toMatchObject([{ title: "Copying into paper stopped", body: "CopyTrading hit a problem it couldn't fix. Stop copying everywhere, then start again to reopen it." }])
  })

  it("says copying is paused when it was on at the last quit, and then every half hour in trading hours", async () => {
    const r = rig({ wasOn: true, status: { state: "paused" } })
    await r.monitor.tick()
    expect(r.notes).toMatchObject([{ title: "Copying is paused", body: "Copying paused when CopyTrading quit. Open CopyTrading and press Start Copying." }])
    await r.monitor.tick()
    expect(r.notes).toHaveLength(1)
    r.state.now = new Date("2026-11-03T15:31:00Z")
    await r.monitor.tick()
    expect(r.notes).toHaveLength(2)
  })

  it("says nothing of a pause when copying was not on, or there is no setup, or copying runs", async () => {
    for (const r of [rig({ wasOn: false, status: { state: "paused" } }), rig({ wasOn: true, setup: false, status: { state: "paused" } }), rig({ wasOn: true, status: { state: "running" } })]) {
      await r.monitor.tick()
      expect(r.notes).toEqual([])
    }
  })

  it("ends the pause notice when copying runs again, and remembers copying is on", async () => {
    const r = rig({ wasOn: true, status: { state: "running" } })
    await r.monitor.tick()
    r.state.status = { state: "paused", accounts: [] } as unknown as TradingStatus
    await r.monitor.tick()
    expect(r.notes).toEqual([])
  })

  it("skips a read the engine cannot answer, and tries again", async () => {
    const r = rig({ posts: [post([{}])] })
    r.state.down = true
    await r.monitor.tick()
    r.state.down = false
    await r.monitor.tick()
    expect(r.notes).toHaveLength(1)
  })

  it("stops reading when stopped, so a status on the way down is never remembered", async () => {
    vi.useFakeTimers()
    const r = rig({ wasOn: true, status: { state: "running" } })
    r.monitor.start()
    await vi.advanceTimersByTimeAsync(2100)
    r.monitor.stop()
    r.state.status = { state: "paused", accounts: [] } as unknown as TradingStatus
    await vi.advanceTimersByTimeAsync(10_000)
    expect(r.saves).toEqual([])
  })
})
