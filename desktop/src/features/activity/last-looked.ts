import { useState, useSyncExternalStore } from "react"

// "Last looked": the moment the owner last saw Activity for a few seconds, or dismissed the card of what came in since. That card counts
// from it. The card reads a frozen copy (`since`) so it cannot empty itself when the saved moment moves on while it is on screen.

const KEY = "copytrading.lastLooked"
/** Away this long (the window hidden or unfocused), and coming back counts from the last look again. */
export const AWAY_MS = 30 * 60 * 1000
/** Viewing Activity this long counts as having looked. */
export const LOOK_MS = 5000

type Saved = Pick<Storage, "getItem" | "setItem">

export function createLastLooked(storage: Saved, seeded: string | null) {
  let since: Date | null = null
  let started = false
  const listeners = new Set<() => void>()
  const notify = () => listeners.forEach((listen) => listen())
  const saved = (): Date | null => {
    const raw = seeded ?? storage.getItem(KEY)
    const at = raw ? new Date(raw) : null
    return at && Number.isFinite(at.getTime()) ? at : null
  }
  // A seeded moment (fixtures) is never written over, so a capture or test never changes what the next one reads.
  const save = (now: Date) => {
    if (seeded === null) storage.setItem(KEY, now.toISOString())
  }
  return {
    /** The moment the card counts from, or null: never looked (the first run saves now and shows nothing), or the card was dismissed. */
    since: () => since,
    /** The app has opened: count from the last look. Does nothing after the first call. */
    begin(now: Date) {
      if (started) return
      started = true
      since = saved()
      if (since === null) save(now)
    },
    /** The owner has looked: the next opening counts from now. The card on screen keeps its own start. */
    looked: save,
    dismiss(now: Date) {
      save(now)
      since = null
      notify()
    },
    /** The window is back after `awayMs`: a long absence counts again from the last look. */
    returned(awayMs: number) {
      if (awayMs < AWAY_MS) return
      since = saved()
      notify()
    },
    subscribe(listen: () => void) {
      listeners.add(listen)
      return () => listeners.delete(listen)
    },
  }
}

let shared: ReturnType<typeof createLastLooked> | null = null
function store() {
  if (!shared) {
    shared = createLastLooked(window.localStorage, new URLSearchParams(window.location.search).get("lastLooked"))
    let leftAt: number | null = null
    const leave = () => void (leftAt ??= Date.now())
    const back = () => {
      if (leftAt !== null) shared!.returned(Date.now() - leftAt)
      leftAt = null
    }
    document.addEventListener("visibilitychange", () => (document.hidden ? leave() : back()))
    window.addEventListener("blur", leave)
    window.addEventListener("focus", back)
  }
  return shared
}

/** Where the card of what came in counts from now: null when the card was dismissed or this is a first run. */
export function useCatchUpSince(now: Date): Date | null {
  useState(() => store().begin(now))
  return useSyncExternalStore(store().subscribe, store().since, () => null)
}

/** Both read the last look before they replace it, so a look that comes before the card has started cannot hide what came in. */
export function dismissCatchUp(now: Date) {
  store().begin(now)
  store().dismiss(now)
}
export function markLooked(now: Date) {
  store().begin(now)
  store().looked(now)
}
