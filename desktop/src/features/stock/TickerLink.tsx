import { useState } from "react"
import styles from "./stock.module.css"
import { stockHref } from "./stock-link"

/** Tickers the logo cache can fetch; a coin's pair or anything else gets the letter alone. */
const HAS_LOGO = /^[A-Z][A-Z0-9.]{0,9}$/

/** A company's logo (the app's logo cache), or its first letter when there is none. */
export function SymbolMark({ symbol, size = 32 }: { symbol: string; size?: number }) {
  const ticker = symbol.toUpperCase()
  const [failed, setFailed] = useState(false)
  return (
    <span className={styles.mark} style={{ width: size, height: size }} aria-hidden="true">
      {HAS_LOGO.test(ticker) && !failed ? <img src={`ct-logo://${ticker}`} alt="" onError={() => setFailed(true)} /> : ticker.charAt(0)}
    </span>
  )
}

/** A ticker that opens that stock's page. Every place that shows a ticker as a link uses this one. */
export function TickerLink({ symbol, accountId, className }: { symbol: string; accountId?: string | null; className?: string }) {
  return (
    <a href={stockHref(symbol, accountId)} className={[styles.ticker, className].filter(Boolean).join(" ")}>
      {symbol}
    </a>
  )
}
