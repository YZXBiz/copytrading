import { useCallback, useEffect, useState } from "react"

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

export interface Recent {
  sourceId: string
  text: string
}

/** The skipped calls, the last one for Undo while it can still be undone, and the two ways to change them. */
export function useSkippedCalls() {
  const [skipped, setSkipped] = useState<Skipped>(() => readSkipped(localStorage, Date.now()))
  const [recent, setRecent] = useState<Recent | null>(null)

  const save = (next: Skipped) => {
    localStorage.setItem(KEY, JSON.stringify(next))
    setSkipped(next)
  }
  const skip = (sourceId: string, text: string) => {
    save({ ...skipped, [sourceId]: Date.now() })
    setRecent({ sourceId, text })
  }
  const undo = () => {
    if (!recent) return
    const { [recent.sourceId]: _, ...rest } = skipped
    save(rest)
    setRecent(null)
  }
  useEffect(() => {
    if (!recent) return
    const timer = setTimeout(() => setRecent(null), UNDO_MS)
    return () => clearTimeout(timer)
  }, [recent])

  return { has: useCallback((sourceId: string) => sourceId in skipped, [skipped]), skip, undo, recent }
}
