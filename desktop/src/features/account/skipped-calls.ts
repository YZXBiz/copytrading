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

/** The last skip, for Undo while it can still be undone: every call it skipped, and the guru's words when it was one. */
export interface Recent {
  sourceIds: string[]
  text: string
}

// One store for the whole window: the account page, ⌘K and the menu bar's count must all see the same skips. A skip is
// written to localStorage and told to main (which keeps the list for the menu bar), and the last one stays undoable.
// Read on first use, so importing this file touches no storage.
let loaded: Skipped | null = null
const skippedNow = (): Skipped => (loaded ??= readSkipped(localStorage, Date.now()))
let recent: Recent | null = null
let timer: ReturnType<typeof setTimeout> | undefined
const listeners = new Set<() => void>()

const tellMain = () => void window.copytrading?.act.setSkippedCalls({ ids: Object.keys(skippedNow()) })
function change(next: Skipped, last: Recent | null) {
  loaded = next
  recent = last
  localStorage.setItem(KEY, JSON.stringify(next))
  tellMain()
  clearTimeout(timer)
  if (last) timer = setTimeout(() => change(skippedNow(), null), UNDO_MS)
  listeners.forEach((listener) => listener())
}

/** Skips every call in `entries` at once; one Undo brings them all back. */
export function skipCalls(entries: { sourceId: string; text: string }[]): void {
  if (entries.length === 0) return
  const now = Date.now()
  const text = entries.length === 1 ? entries[0]!.text : ""
  change({ ...skippedNow(), ...Object.fromEntries(entries.map((e) => [e.sourceId, now])) }, { sourceIds: entries.map((e) => e.sourceId), text })
}

export function undoSkip(): void {
  if (!recent) return
  const back = new Set(recent.sourceIds)
  change(Object.fromEntries(Object.entries(skippedNow()).filter(([id]) => !back.has(id))), null)
}

/** The window tells main what is skipped when it opens, so a count made before any skip is not too high. */
export const announceSkipped = tellMain

const subscribe = (listener: () => void) => (listeners.add(listener), () => listeners.delete(listener))

/** The skipped calls and the last skip, the same everywhere, and the ways to change them. */
export function useSkippedCalls() {
  const now = useSyncExternalStore(subscribe, skippedNow)
  const last = useSyncExternalStore(subscribe, () => recent)
  return { has: (sourceId: string) => sourceId in now, skip: (sourceId: string, text: string) => skipCalls([{ sourceId, text }]), skipAll: skipCalls, undo: undoSkip, recent: last }
}
