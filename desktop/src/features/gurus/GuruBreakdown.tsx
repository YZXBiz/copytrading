import type { GuruPerformance } from "../../../shared/contract"
import { Badge } from "@/components/arc/badge/badge"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import { RegionAlert } from "@/features/activity/RegionAlert"
import { TickerLink } from "@/features/stock/TickerLink"
import { monthDay, signedMoney } from "@/lib/format"
import styles from "./gurus.module.css"

interface Row {
  name: string
  /** The ticker, beside the name. */
  code?: string
  /** The date, under the name. */
  note?: string
  title?: string
  amount: number | null
}

const tone = (n: number | null) => (n === null || n === 0 ? undefined : n > 0 ? "gain" : "loss")
const unmatchedNote = (n: number) => `${n === 1 ? "1 sale" : `${n} sales`} could not be matched to the buys it closed, so ${n === 1 ? "it is" : "they are"} left out.`

/** The guru's best and worst call, what is still open, and the sales that could not be matched to a buy. */
export function GuruBreakdown({ performance, accountId, error, onRetry }: { performance: GuruPerformance | null; accountId: string; error: string | null; onRetry: () => void }) {
  const rows: Row[] = performance
    ? [
        ...(performance.best ? [{ name: "Best call", code: performance.best.symbol, note: monthDay(`${performance.best.closed_on}T12:00:00Z`), title: performance.best.excerpt ?? undefined, amount: Number(performance.best.profit_usd) }] : []),
        ...(performance.worst ? [{ name: "Worst call", code: performance.worst.symbol, note: monthDay(`${performance.worst.closed_on}T12:00:00Z`), title: performance.worst.excerpt ?? undefined, amount: Number(performance.worst.profit_usd) }] : []),
        { name: "Unrealized P&L", amount: performance.unrealized_usd === null ? null : Number(performance.unrealized_usd) },
      ]
    : []
  return (
    <section className={styles.panel} aria-labelledby="breakdown-title">
      <div className={styles.panelHead}>
        <h2 id="breakdown-title">Breakdown</h2>
        <p>Best and worst call, and what is still open</p>
      </div>
      {!performance && !error && <Skeleton label="Loading breakdown" lines={3} />}
      {error && <RegionAlert title="Performance did not load" message={error} onRetry={onRetry} />}
      {rows.length > 0 && (
        <ul className={styles.rows}>
          {rows.map((row) => (
            <li key={row.name} title={row.title}>
              <span className={styles.rowName}>
                <span>
                  {row.name}
                  {row.code && (
                    <Badge tone="neutral">
                      <TickerLink symbol={row.code} accountId={accountId} />
                    </Badge>
                  )}
                </span>
                {row.note && <small>{row.note}</small>}
              </span>
              <span className={styles.amount} data-tone={tone(row.amount)}>
                {row.amount === null ? "None" : signedMoney(row.amount)}
              </span>
            </li>
          ))}
          {performance && performance.unmatched_sells > 0 && (
            <li>
              <span className={styles.rowName}>
                <span>Unmatched sells</span>
                <small>{unmatchedNote(performance.unmatched_sells)}</small>
              </span>
              <span className={styles.amount}>{performance.unmatched_sells}</span>
            </li>
          )}
        </ul>
      )}
      {performance && performance.closed_trades === 0 && <p className={styles.note}>No closed trades yet, so there is no best or worst call.</p>}
    </section>
  )
}
