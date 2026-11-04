import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

// The store keeps its state in the module, so each test loads a fresh one against stand-in storage.
async function load() {
  vi.resetModules()
  const data = new Map<string, string>()
  const told: string[][] = []
  vi.stubGlobal("localStorage", { getItem: (k: string) => data.get(k) ?? null, setItem: (k: string, v: string) => void data.set(k, v) })
  vi.stubGlobal("window", { copytrading: { act: { setSkippedCalls: async ({ ids }: { ids: string[] }) => void told.push(ids) } } })
  return { ...(await import("./skipped-calls")), told, data }
}

beforeEach(() => vi.useFakeTimers())
afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllGlobals()
})

describe("skipping several calls", () => {
  it("skips them together, tells main, and one Undo brings every one back", async () => {
    const store = await load()
    store.skipCalls([{ sourceId: "a", text: "x" }, { sourceId: "b", text: "y" }])
    expect(JSON.parse(store.data.get("skippedWaitingCalls")!)).toHaveProperty("a")
    expect(store.told.at(-1)).toEqual(["a", "b"])
    store.undoSkip()
    expect(store.told.at(-1)).toEqual([])
    expect(JSON.parse(store.data.get("skippedWaitingCalls")!)).toEqual({})
  })

  it("undoes only the last skip, and not after its time is up", async () => {
    const store = await load()
    store.skipCalls([{ sourceId: "a", text: "x" }])
    store.skipCalls([{ sourceId: "b", text: "y" }])
    store.undoSkip()
    expect(store.told.at(-1)).toEqual(["a"])
    store.skipCalls([{ sourceId: "c", text: "z" }])
    vi.advanceTimersByTime(store.UNDO_MS + 1)
    store.undoSkip()
    expect(store.told.at(-1)).toEqual(["a", "c"])
  })

  it("does nothing for an empty list", async () => {
    const store = await load()
    store.skipCalls([])
    expect(store.told).toEqual([])
  })
})
