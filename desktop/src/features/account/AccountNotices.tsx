import type { AccountOverview, TradingStatus } from "../../../shared/contract"
import { Alert } from "@/components/arc/alert/alert"
import { STOPPED_BODY, accountCopying, stoppedTitle } from "./copying"
import { OwnershipRow } from "./OwnershipRow"
import { reasonText } from "@/lib/reasons"
import styles from "./account.module.css"

/** A check that simply hasn't run yet, as while copying is off, is not a warning and stays out of sight. */
const shown = (reason: string | null | undefined) => (reason && reason !== "not_checked" ? reason : null)

/** What needs the owner's eye about the account itself: it stopped, its risk or orders, and holdings that don't add up. */
export function AccountNotices({
  account,
  status,
  onResolved,
}: {
  account: AccountOverview
  status: TradingStatus | null
  onResolved: () => void
}) {
  const state = accountCopying(account, status)
  const risk = shown(account.account_risk_reason)
  const activity = shown(account.account_activity_reason)
  const incidents = account.ownership_incidents ?? []
  const listed = new Set(incidents.map((i) => i.incident_id))
  const unlisted = (account.unresolved_incidents ?? []).filter((id) => !listed.has(id))

  return (
    <>
      {state.word === "stopped" && (
        <Alert tone="danger" title={stoppedTitle(account.account_id)}>
          {state.detail && <p className={styles.alertText}>{state.detail}.</p>}
          <p className={styles.alertText}>{STOPPED_BODY}</p>
        </Alert>
      )}
      {risk && <Alert tone="warning" title={`Risk valuation: ${reasonText(risk)}`} />}
      {activity && (
        <Alert tone="warning" title={activity === "unresolved_account_order" ? "An order in Alpaca that CopyTrading didn't place is still open" : reasonText(activity)}>
          <p className={styles.alertText}>
            {activity === "unresolved_account_order" ? "Let it fill or cancel it in Alpaca. Until it's gone, CopyTrading can't settle holdings." : "CopyTrading checks again on the next sync."}
          </p>
        </Alert>
      )}
      {incidents.map((incident) => (
        <OwnershipRow key={incident.incident_id} incident={incident} account={account} blocked={activity !== null} onResolved={onResolved} />
      ))}
      {unlisted.length > 0 && <Alert tone="danger" title={`Unresolved incidents: ${unlisted.join(", ")}`} />}
    </>
  )
}
