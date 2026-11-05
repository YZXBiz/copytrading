import type { GuruPerformance } from "../../../shared/contract"
import { MetricCard } from "@/components/arc/metric-card/metric-card"
import { monthDay, signedMoney } from "@/lib/format"
import type { Holdings, Stats } from "./model"
import styles from "./gurus.module.css"

/** A money figure as the counter shows it: the sign goes in front, the amount is the absolute value. */
const money = (value: number, signed: boolean) => ({ value: Math.abs(value), prefix: `${value < 0 ? "−" : signed && value > 0 ? "+" : ""}$`, decimals: 2 })

/**
 * Posts today, win rate, realized profit and what is held. Before a figure is read it is a quiet bar, never a zero that was not
 * counted; nothing held reads as "None" with its line saying so.
 */
export function GuruKpis({ stats, performance, holdings }: { stats: Stats; performance: GuruPerformance | null; holdings: Holdings | null | undefined }) {
  const realized = performance ? Number(performance.realized_usd) : null
  const closed = performance?.closed_trades ?? 0
  const first = performance?.series[0]
  const held = holdings ? holdings.cost + holdings.gain : null
  const postsContext =
    stats.postsToday === null ? "Reading today's posts" : `${(stats.tradedToday ?? 0).toLocaleString("en-US")} traded, ${stats.waiting.toLocaleString("en-US")} waiting`
  const realizedMoney = realized === null ? null : money(realized, true)
  const heldMoney = held === null ? null : money(held, false)
  return (
    <div className={styles.kpis}>
      <MetricCard label="Posts today" value={stats.postsToday} pending={stats.postsToday === null} context={postsContext} />
      <MetricCard
        label="Win rate"
        value={performance && closed > 0 ? Math.round((performance.winning_trades / closed) * 100) : null}
        suffix="%"
        pending={!performance}
        context={performance ? (closed > 0 ? `${performance.winning_trades} of ${closed} closed trades` : "No closed trades yet") : "Reading trades"}
      />
      <MetricCard
        label="Realized P&L"
        value={realizedMoney?.value ?? null}
        prefix={realizedMoney?.prefix}
        decimals={2}
        tone={realized === null || realized === 0 ? undefined : realized > 0 ? "gain" : "loss"}
        pending={!performance}
        context={first ? `Since ${monthDay(`${first.day}T12:00:00Z`)}` : performance ? "No sales closed yet" : "Reading trades"}
      />
      <MetricCard
        label="Holding value"
        value={heldMoney?.value ?? null}
        prefix={heldMoney?.prefix}
        decimals={2}
        pending={holdings === undefined}
        context={holdings ? `${signedMoney(holdings.gain)} in ${holdings.stocks === 1 ? "1 stock" : `${holdings.stocks} stocks`}` : holdings === null ? "Nothing held from this guru" : "Reading holdings"}
      />
    </div>
  )
}
