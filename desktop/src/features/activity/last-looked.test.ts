import { describe, expect, it } from "vitest"
import { AWAY_MS, createLastLooked } from "./last-looked"

const memory = (initial: Record<string, string> = {}) => {
  const data = { ...initial }
  return { data, getItem: (k: string) => data[k] ?? null, setItem: (k: string, v: string) => void (data[k] = v) }
}
const T = (hours: number) => new Date(Date.UTC(2026, 10, 4, hours))

describe("last looked", () => {
  it("shows nothing on a first run and remembers now", () => {
    const storage = memory()
    const looked = createLastLooked(storage, null)
    looked.begin(T(9))
    expect(looked.since()).toBeNull()
    expect(storage.data["copytrading.lastLooked"]).toBe(T(9).toISOString())
  })

  it("counts from the last look and keeps that start while a later look is saved", () => {
    const storage = memory({ "copytrading.lastLooked": T(9).toISOString() })
    const looked = createLastLooked(storage, null)
    looked.begin(T(12))
    looked.looked(T(12))
    expect(looked.since()).toEqual(T(9))
    expect(storage.data["copytrading.lastLooked"]).toBe(T(12).toISOString())
  })

  it("dismissing clears the card and moves the last look to now", () => {
    const looked = createLastLooked(memory({ "copytrading.lastLooked": T(9).toISOString() }), null)
    let changes = 0
    looked.subscribe(() => changes++)
    looked.begin(T(12))
    looked.dismiss(T(13))
    expect(looked.since()).toBeNull()
    expect(changes).toBe(1)
  })

  it("counts from the last look again only after a long absence", () => {
    const looked = createLastLooked(memory({ "copytrading.lastLooked": T(9).toISOString() }), null)
    looked.begin(T(12))
    looked.dismiss(T(12))
    looked.returned(AWAY_MS - 1)
    expect(looked.since()).toBeNull()
    looked.returned(AWAY_MS)
    expect(looked.since()).toEqual(T(12))
  })

  it("never writes over a seeded moment", () => {
    const storage = memory()
    const looked = createLastLooked(storage, T(8).toISOString())
    looked.begin(T(12))
    looked.looked(T(12))
    expect(looked.since()).toEqual(T(8))
    expect(storage.data).toEqual({})
  })
})
