import { useCallback, useEffect, useState } from "react"
import type { Result } from "../../shared/contract"

export type Loaded<T> =
  | { status: "loading" }
  | { status: "error"; error: string }
  | { status: "ready"; data: T }

/** Loads one bridge read; `retry` runs it again. A change in `key` starts over with a skeleton. */
export function useResult<T>(load: () => Promise<Result<T>>, key: string): Loaded<T> & { retry: () => void } {
  const [state, setState] = useState<Loaded<T>>({ status: "loading" })
  const [attempt, setAttempt] = useState(0)

  useEffect(() => {
    let current = true
    setState({ status: "loading" })
    load().then(
      (result) => {
        if (current) setState(result.ok ? { status: "ready", data: result.value } : { status: "error", error: result.error })
      },
      (error: unknown) => {
        if (current) setState({ status: "error", error: error instanceof Error ? error.message : "The request failed." })
      },
    )
    return () => {
      current = false
    }
    // `load` is a fresh closure each render; `key` and `attempt` say when to read again.
  }, [key, attempt])

  const retry = useCallback(() => setAttempt((n) => n + 1), [])
  return { ...state, retry }
}
