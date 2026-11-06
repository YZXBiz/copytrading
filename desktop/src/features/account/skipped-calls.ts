import { useSyncExternalStore } from "react"

// The waiting calls the owner chose to skip (SkippedCalls.swift, ADR-0007). Skipping places nothing and changes
// nothing in the engine: it only takes a call off the owner's list, so it is kept in the app's storage and
// forgotten after a week, long after the call itself has expired.

const KEY = "skippedWaitingCalls"
const KEPT_MS = 7 * 24 * 3600 * 1000
/** How long a skip can be undone in place. */
export const UNDO_MS = 10_000

export type Skipped = Record<string, number>

/** What is still worth keeping at `now`. */
export const pruneSkipped = (skipped: Skipped, now: number): Skipped =>
  Object.fromEntries(Object.entries(skipped).filter(([, at]) => now - at < KEPT_MS))

export function readSkipped(storage: Pick<Storage, "getItem">, now: number): Skipped {
  try {
    const stored: unknown = JSON.parse(storage.getItem(KEY) ?? "{}")
    return stored && typeof stored === "object" && !Array.isArray(stored) ? pruneSkipped(stored as Skipped, now) : {}
  } catch {
    return {}
  }
}

// One store for the whole window: the account page, ⌘K and the menu bar's count must all see the same skips. A skip is
// written to localStorage and told to main (which keeps the list for the menu bar) at once; the undo window itself
// belongs to whoever shows the toast, which brings the same calls back with `unskipCalls`.
// Read on first use, so importing this file touches no storage.
let loaded: Skipped | null = null
const skippedNow = (): Skipped => (loaded ??= readSkipped(localStorage, Date.now()))
const listeners = new Set<() => void>()

const tellMain = () => void window.copytrading?.act.setSkippedCalls({ ids: Object.keys(skippedNow()) })
function change(next: Skipped) {
  loaded = next
  localStorage.setItem(KEY, JSON.stringify(next))
  tellMain()
  listeners.forEach((listener) => listener())
}

/** Skips every call in `sourceIds` at once. */
export function skipCalls(sourceIds: string[]): void {
  if (sourceIds.length === 0) return
  const now = Date.now()
  change({ ...skippedNow(), ...Object.fromEntries(sourceIds.map((id) => [id, now])) })
}

/** Brings exactly these calls back, however many skips came since. */
export function unskipCalls(sourceIds: string[]): void {
  const back = new Set(sourceIds)
  change(Object.fromEntries(Object.entries(skippedNow()).filter(([id]) => !back.has(id))))
}

/** The window tells main what is skipped when it opens, so a count made before any skip is not too high. */
export const announceSkipped = tellMain

const subscribe = (listener: () => void) => (listeners.add(listener), () => listeners.delete(listener))

/** The skipped calls, the same everywhere, and the ways to change them. */
export function useSkippedCalls() {
  const now = useSyncExternalStore(subscribe, skippedNow)
  return { has: (sourceId: string) => sourceId in now, skip: skipCalls, unskip: unskipCalls }
}
