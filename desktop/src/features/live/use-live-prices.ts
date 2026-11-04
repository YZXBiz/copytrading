import { useEffect, useState } from "react"
import { canQuote } from "@/features/account/quote"
import { readClock } from "@/lib/clock"
import { everyWhileVisible } from "@/lib/visible-interval"
import { TICK_MS, markPrice } from "./live"

/**
 * A live price for each held stock, through one account's read keys, every 5 s while the window is visible. A failed
 * or stale quote leaves the last live price standing, and a stock with none shows the broker's own price.
 */
export function useLivePrices(accountId: string, symbols: string[]): Record<string, number> {
  const [prices, setPrices] = useState<Record<string, number>>({})
  const key = [...new Set(symbols.filter(canQuote))].sort().join(",")
  useEffect(() => {
    setPrices({})
  }, [accountId])
  useEffect(() => {
    if (!key) return
    let current = true
    const askAll = () =>
      key.split(",").forEach((symbol) =>
        void window.copytrading.read.getQuote({ account_id: accountId, symbol }).then((result) => {
          const price = result.ok ? markPrice(result.value, readClock()) : null
          if (current && price !== null) setPrices((p) => (p[symbol] === price ? p : { ...p, [symbol]: price }))
        }, () => undefined),
      )
    const stop = everyWhileVisible(askAll, TICK_MS)
    return () => {
      current = false
      stop()
    }
  }, [accountId, key])
  return prices
}
