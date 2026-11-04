import { useCallback, useEffect, useState } from "react"
import type { Result } from "../../shared/contract"

export type Loaded<T> =
  | { status: "loading" }
  | { status: "error"; error: string }
  | { status: "ready"; data: T }

const failed = (error: unknown) => (error instanceof Error ? error.message : "The request failed.")

/**
 * Loads one bridge read; `retry` runs it again. A change in `key` starts over with a skeleton. With `everyMs` it
 * reads again on that interval without a skeleton, and a failed re-read keeps what is shown.
 */
export function useResult<T>(load: () => Promise<Result<T>>, key: string, everyMs?: number): Loaded<T> & { retry: () => void } {
  const [state, setState] = useState<Loaded<T>>({ status: "loading" })
  const [attempt, setAttempt] = useState(0)

  useEffect(() => {
    let current = true
    const read = (quiet: boolean) =>
      load().then(
        (result) => {
          if (!current) return
          if (result.ok) setState({ status: "ready", data: result.value })
          else setState((shown) => (quiet && shown.status === "ready" ? shown : { status: "error", error: result.error }))
        },
        (error: unknown) => {
          if (current) setState((shown) => (quiet && shown.status === "ready" ? shown : { status: "error", error: failed(error) }))
        },
      )
    setState({ status: "loading" })
    void read(false)
    const timer = everyMs ? setInterval(() => void read(true), everyMs) : undefined
    return () => {
      current = false
      clearInterval(timer)
    }
    // `load` is a fresh closure each render; `key` and `attempt` say when to read again.
  }, [key, attempt, everyMs])

  const retry = useCallback(() => setAttempt((n) => n + 1), [])
  return { ...state, retry }
}
