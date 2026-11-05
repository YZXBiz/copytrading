import type { ReactNode } from "react"
import type { AccountOverview } from "../../../shared/contract"
import { AnimatedCounter } from "@/components/arc/animated-counter/animated-counter"
import { percent } from "@/lib/format"
import styles from "./account.module.css"

const money = (text: string | null | undefined) => (text == null || text === "" || !Number.isFinite(Number(text)) ? null : Number(text))

function Figure({ label, context, children, onClick }: { label: string; context: string; children: ReactNode; onClick?: () => void }) {
  const body = (
    <>
      <span className={styles.figureLabel}>{label}</span>
      <span className={styles.figureValue}>{children}</span>
      <span className={styles.figureContext}>{context}</span>
    </>
  )
  return <li>{onClick ? <button type="button" className={styles.figure} onClick={onClick}>{body}</button> : <div className={styles.figure}>{body}</div>}</li>
}

const Dollars = ({ value }: { value: number | null }) => (value === null ? <span className={styles.muted}>No figure yet</span> : <AnimatedCounter value={value} prefix="$" decimals={2} />)

/** Cash, buying power, what CopyTrading has invested, and the calls waiting for the owner. */
export function Figures({ account, waiting, onShowWaiting }: { account: AccountOverview; waiting: number; onShowWaiting: () => void }) {
  const balance = account.balance
  const equity = Number(balance?.equity)
  const share = (part: string | null | undefined) => (equity > 0 && part != null ? `${percent(Number(part) / equity, 0)} of equity` : "In the account")
  return (
    <ul className={styles.figures} aria-label="Account figures">
      <Figure label="Cash" context={share(balance?.cash)}>
        <Dollars value={money(balance?.cash)} />
      </Figure>
      <Figure label="Buying power" context="Available to spend">
        <Dollars value={money(balance?.buying_power)} />
      </Figure>
      <Figure label="Invested by CopyTrading" context={account.pending_orders ? `${account.pending_orders} ${account.pending_orders === 1 ? "order" : "orders"} waiting` : share(account.total_exposure_usd)}>
        <Dollars value={money(account.total_exposure_usd ?? "0")} />
      </Figure>
      <Figure label="Waiting for you" context={waiting === 0 ? "All answered" : "Calls to answer"} onClick={onShowWaiting}>
        <AnimatedCounter value={waiting} />
      </Figure>
    </ul>
  )
}
