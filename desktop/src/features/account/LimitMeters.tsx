import { useId } from "react"
import type { AccountLimits, AccountOverview } from "../../../shared/contract"
import { Button } from "@/components/arc/button/button"
import { ThresholdBar } from "@/components/arc/blocks/spend-alert/spend-alert"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import { money } from "@/lib/format"
import { type Loaded } from "@/lib/use-result"
import styles from "./account.module.css"
import { RegionNote } from "./RegionNote"

/** The limit sits at the end of the bar: what is used fills toward it, and turns red once it is reached. */
function Meter({ label, used, cap, usedText, capText }: { label: string; used: number; cap: number; usedText: string; capText: string }) {
  const id = useId()
  const share = cap > 0 ? Math.min(100, (used / cap) * 100) : 0
  return (
    <div className={styles.meter}>
      <div className={styles.meterHead}>
        <span id={id}>{label}</span>
        <span className={styles.meterShare}>{cap > 0 ? `${Math.round((used / cap) * 100)}%` : "No limit"}</span>
      </div>
      <ThresholdBar
        value={100}
        onChange={() => undefined}
        spendPct={share}
        forecastPct={share}
        markers={[100]}
        labelId={id}
        valueText={`${usedText} of ${capText}`}
        disabled
        over={cap > 0 && used >= cap}
      />
      <div className={styles.meterFoot}>
        <span>{usedText}</span>
        <span>{capText}</span>
      </div>
    </div>
  )
}

/** The account's loss and invested limits as bars, and the three that are numbers. They change only in Edit limits. */
export function LimitMeters({ account, limits, onOpenConnections }: { account: AccountOverview; limits: Loaded<AccountLimits | null> & { retry: () => void }; onOpenConnections: () => void }) {
  const lossToday = Math.max(0, -Number(account.balance?.day_change_usd ?? 0))
  const set = limits.status === "ready" ? limits.data : null
  return (
    <section className={styles.panel} aria-labelledby="limits-title">
      <header className={styles.panelHead}>
        <h2 id="limits-title" className={styles.panelTitle}>
          Limits
        </h2>
      </header>
      {limits.status === "loading" && <Skeleton label="Loading limits" lines={4} />}
      {limits.status === "error" && <RegionNote title="Limits did not load" message={limits.error} onRetry={limits.retry} />}
      {limits.status === "ready" && !set && (
        <EmptyState
          title="No limits to show"
          description="Save the account in Connections first."
          action={
            <Button type="button" variant="secondary" size="sm" onClick={onOpenConnections}>
              Open Connections
            </Button>
          }
        />
      )}
      {set && (
        <>
          <Meter label="Loss today" used={lossToday} cap={set.daily_loss_cap_usd} usedText={`${money(lossToday)} lost`} capText={`${money(set.daily_loss_cap_usd)} limit`} />
          <Meter label="Invested" used={Number(account.total_exposure_usd ?? 0)} cap={set.max_total_usd} usedText={`${money(account.total_exposure_usd ?? 0)} invested`} capText={`${money(set.max_total_usd)} total`} />
          <dl className={styles.limitFacts}>
            {[
              ["Each order", money(set.max_order_usd)],
              ["Each stock", money(set.max_symbol_usd)],
              ["Buys per day", String(set.max_entries_per_day)],
            ].map(([label, value]) => (
              <div key={label}>
                <dt>{label}</dt>
                <dd>{value}</dd>
              </div>
            ))}
          </dl>
        </>
      )}
    </section>
  )
}
