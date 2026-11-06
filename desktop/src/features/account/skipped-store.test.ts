import { afterEach, describe, expect, it, vi } from "vitest"

// The store keeps its state in the module, so each test loads a fresh one against stand-in storage.
async function load() {
  vi.resetModules()
  const data = new Map<string, string>()
  const told: string[][] = []
  vi.stubGlobal("localStorage", { getItem: (k: string) => data.get(k) ?? null, setItem: (k: string, v: string) => void data.set(k, v) })
  vi.stubGlobal("window", { copytrading: { act: { setSkippedCalls: async ({ ids }: { ids: string[] }) => void told.push(ids) } } })
  return { ...(await import("./skipped-calls")), told, data }
}

afterEach(() => vi.unstubAllGlobals())

describe("skipping calls", () => {
  it("skips several together and tells main", async () => {
    const store = await load()
    store.skipCalls(["a", "b"])
    expect(JSON.parse(store.data.get("skippedWaitingCalls")!)).toHaveProperty("a")
    expect(store.told.at(-1)).toEqual(["a", "b"])
  })

  it("brings back exactly the calls named, however many skips came after", async () => {
    const store = await load()
    store.skipCalls(["a"])
    store.skipCalls(["b"])
    store.skipCalls(["c"])
    store.unskipCalls(["a", "b"])
    expect(store.told.at(-1)).toEqual(["c"])
    store.unskipCalls(["c"])
    expect(JSON.parse(store.data.get("skippedWaitingCalls")!)).toEqual({})
  })

  it("does nothing for an empty list", async () => {
    const store = await load()
    store.skipCalls([])
    expect(store.told).toEqual([])
  })
})
