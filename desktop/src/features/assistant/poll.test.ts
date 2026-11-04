import { describe, expect, it } from "vitest"
import type { AssistantTurnPage, Result } from "../../../shared/contract"
import { type Event, pollTurn } from "./poll"

const ev = (seq: number, kind = "text"): Event => ({ seq, kind, text: `t${seq}`, link: null, proposal_id: null, code: null })
const page = (events: Event[], done = false): Result<AssistantTurnPage> => ({ ok: true, value: { turn_id: "t-0123456789ab", done, events } })

function run(pages: Result<AssistantTurnPage>[], isCurrent: () => boolean = () => true) {
  const asked: number[] = []
  const seen: number[] = []
  let slept = 0
  const result = pollTurn({
    readTurn: async (after) => (asked.push(after), pages.shift() ?? page([], true)),
    isCurrent,
    onEvents: (events) => seen.push(...events.map((e) => e.seq)),
    sleep: async () => void slept++,
  })
  return { result, asked, seen, slept: () => slept }
}

describe("pollTurn", () => {
  it("asks for each page after the last event it saw, and stops when the engine says done", async () => {
    const r = run([page([ev(1), ev(2)]), page([ev(3)], true)])
    expect(await r.result).toBe("done")
    expect(r.asked).toEqual([0, 2])
    expect(r.seen).toEqual([1, 2, 3])
  })

  it("stops on a `done` event even if the page is not marked done", async () => {
    const r = run([page([ev(1), ev(2, "done")])])
    expect(await r.result).toBe("done")
    expect(r.asked).toEqual([0])
  })

  it("waits between pages with nothing new", async () => {
    const r = run([page([]), page([]), page([ev(1)], true)])
    await r.result
    expect(r.slept()).toBe(2)
  })

  it("reports an error from the engine and stops", async () => {
    const r = run([page([ev(1)]), { ok: false, error: "The engine did not answer." }])
    expect(await r.result).toEqual({ error: "The engine did not answer." })
    expect(r.seen).toEqual([1])
  })

  it("drops a page that arrives after a reset, without showing it", async () => {
    let current = true
    const r = run([page([ev(1)]), page([ev(2)])], () => current)
    // The reset lands while the first page is in flight.
    current = false
    expect(await r.result).toBe("dropped")
    expect(r.seen).toEqual([])
  })
})
