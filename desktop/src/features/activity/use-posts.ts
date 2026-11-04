import { useCallback, useEffect, useRef, useState } from "react"
import type { Result, SourceActivity, SourceActivityPage } from "../../../shared/contract"
import { mergePosts } from "./outcome"

const PAGE = 40
/** New posts arrive while the screen is open; the newest page is read again this often. */
const REFRESH_MS = 15_000

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
  const [items, setItems] = useState<SourceActivity[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [cursor, setCursor] = useState<number | null>(null)
  const [older, setOlder] = useState<"idle" | "loading" | { error: string }>("idle")
  const [attempt, setAttempt] = useState(0)
  const loadRef = useRef(load)
  loadRef.current = load

  useEffect(() => {
    let current = true
    setItems(null)
    setError(null)
    setCursor(null)
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
      setItems((have) => mergePosts(have ?? [], result.value.items))
      if (first) setCursor(result.value.next_before_seq ?? null)
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

  if (error !== null && items === null) return { status: "error", error, retry: () => setAttempt((n) => n + 1) }
  if (items === null) return { status: "loading" }
  return { status: "ready", items, hasOlder: cursor !== null, showOlder, older }
}
