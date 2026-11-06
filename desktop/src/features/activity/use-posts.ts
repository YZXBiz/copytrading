import { useCallback, useEffect, useRef, useState } from "react"
import type { Result, SourceActivity, SourceActivityPage } from "../../../shared/contract"
import { mergePosts } from "./outcome"

/** The engine's largest page: a month of posts is read in as few requests as it allows. */
const PAGE = 100
/** New posts arrive while the screen is open; the newest page is read again this often. */
const REFRESH_MS = 15_000

// Posts already read stay for the session, per key: reopening a screen shows them at once and reads only the
// newest page. shortcut: an older post's outcome is not re-read after it leaves the newest page; read them all
// again if late fills on old posts start to matter.
const kept = new Map<string, { items: SourceActivity[]; cursor: number | null }>()

/** A full newest page that reaches none of the kept posts leaves a gap between them, so the screen starts over from it. */
export const leavesGap = (kept: SourceActivity[], fresh: SourceActivity[], page: number) =>
  fresh.length === page && !fresh.some((post) => kept.some((k) => k.sequence === post.sequence))

export type Posts =
  | { status: "loading" }
  | { status: "error"; error: string; retry: () => void }
  | {
      status: "ready"
      items: SourceActivity[]
      /** Whether the engine has older posts than the ones loaded. */
      hasOlder: boolean
      showOlder: () => void
      older: "idle" | "loading" | { error: string }
    }

/**
 * Posts newest first, paged: the newest page, kept fresh, then older pages on request. `load` reads one page
 * (`before` is the cursor the last page gave); a change in `key` starts over.
 */
export function usePosts(load: (before: number | undefined, limit: number) => Promise<Result<SourceActivityPage>>, key: string): Posts {
  const [items, setItems] = useState<SourceActivity[] | null>(() => kept.get(key)?.items ?? null)
  const [error, setError] = useState<string | null>(null)
  const [cursor, setCursor] = useState<number | null>(() => kept.get(key)?.cursor ?? null)
  const [older, setOlder] = useState<"idle" | "loading" | { error: string }>("idle")
  const [attempt, setAttempt] = useState(0)
  const loadRef = useRef(load)
  loadRef.current = load

  useEffect(() => {
    let current = true
    const had = kept.get(key)
    setItems(had?.items ?? null)
    setError(null)
    setCursor(had?.cursor ?? null)
    setOlder("idle")
    const read = async (first: boolean) => {
      const result = await loadRef.current(undefined, PAGE).catch((e: unknown): Result<never> => ({ ok: false, error: e instanceof Error ? e.message : "The request failed." }))
      if (!current) return
      if (!result.ok) {
        // A failed refresh keeps the posts on screen; only the first read reports.
        if (first) setError(result.error)
        return
      }
      setError(null)
      const fresh = result.value.items
      const gap = first && had !== undefined && leavesGap(had.items, fresh, PAGE)
      setItems((have) => (gap ? fresh : mergePosts(have ?? [], fresh)))
      if (first && (had === undefined || gap)) setCursor(result.value.next_before_seq ?? null)
    }
    void read(true)
    const timer = window.setInterval(() => void read(false), REFRESH_MS)
    return () => {
      current = false
      window.clearInterval(timer)
    }
  }, [key, attempt])

  const showOlder = useCallback(() => {
    if (cursor === null) return
    setOlder("loading")
    loadRef.current(cursor, PAGE).then(
      (result) => {
        if (!result.ok) return setOlder({ error: result.error })
        setItems((have) => mergePosts(have ?? [], result.value.items))
        setCursor(result.value.next_before_seq ?? null)
        setOlder("idle")
      },
      (e: unknown) => setOlder({ error: e instanceof Error ? e.message : "The request failed." }),
    )
  }, [cursor])

  useEffect(() => {
    if (items !== null) kept.set(key, { items, cursor })
  }, [key, items, cursor])

  if (error !== null && items === null) return { status: "error", error, retry: () => setAttempt((n) => n + 1) }
  if (items === null) return { status: "loading" }
  return { status: "ready", items, hasOlder: cursor !== null, showOlder, older }
}
