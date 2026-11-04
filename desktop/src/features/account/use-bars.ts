import { useEffect, useState } from "react"
import type { Bar } from "../../../shared/contract"
import { everyWhileVisible } from "@/lib/visible-interval"
import { canQuote } from "./quote"

/** The engine caches a symbol's bars for a minute, so asking more often only repeats its answer. */
export const BARS_MS = 60_000

/**
 * The five-minute bars of each held stock's latest session, through the account's read keys: one ask for all of them, every
 * minute while the window is visible. A failed ask keeps the bars shown; a stock with none has none.
 */
export function useBars(accountId: string, symbols: string[]): Record<string, Bar[]> {
  const [bars, setBars] = useState<Record<string, Bar[]>>({})
  const key = [...new Set(symbols.filter(canQuote))].sort().join(",")
  useEffect(() => {
    setBars({})
  }, [accountId])
  useEffect(() => {
    if (!key) return
    let current = true
    const ask = () =>
      void window.copytrading.read.getBars({ account_id: accountId, symbols: key.split(",") }).then(
        (result) => {
          if (current && result.ok) setBars(result.value)
        },
        () => undefined,
      )
    const stop = everyWhileVisible(ask, BARS_MS)
    return () => {
      current = false
      stop()
    }
  }, [accountId, key])
  return bars
}
