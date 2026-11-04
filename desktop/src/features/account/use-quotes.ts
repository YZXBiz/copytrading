import { useCallback, useEffect, useState } from "react"
import type { MarketQuote } from "../../../shared/contract"
import { canQuote } from "./quote"

/** How often an open sheet asks again, so Market always reads a live price. */
const REFRESH_MS = 30_000

/**
 * The broker's latest quote for each stock, through one account's read keys: asked for as the sheet opens, again
 * every half minute, and after a typed ticker settles. A failed ask keeps the last quote, which then says how old it is.
 */
export function useQuotes(accountId: string | null, symbols: string[]) {
  const [quotes, setQuotes] = useState<Record<string, MarketQuote | null>>({})
  const [asking, setAsking] = useState<ReadonlySet<string>>(new Set())

  const ask = useCallback(
    async (symbol: string) => {
      if (!accountId) return
      setAsking((s) => new Set(s).add(symbol))
      const result = await window.copytrading.read.getQuote({ account_id: accountId, symbol })
      setAsking((s) => {
        const next = new Set(s)
        next.delete(symbol)
        return next
      })
      if (result.ok) setQuotes((q) => ({ ...q, [symbol]: result.value }))
    },
    [accountId],
  )

  const key = [...new Set(symbols.filter(canQuote))].sort().join(",")
  useEffect(() => {
    if (!key) return
    const askAll = () => key.split(",").forEach(ask)
    const first = setTimeout(askAll, 400)
    const every = setInterval(askAll, REFRESH_MS)
    return () => {
      clearTimeout(first)
      clearInterval(every)
    }
  }, [key, ask])

  return { quotes, asking, refresh: ask }
}
