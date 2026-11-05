import { useState } from "react"
import type { OwnershipIncident, AccountOverview } from "../../../shared/contract"
import { Alert } from "@/components/arc/alert/alert"
import { Button } from "@/components/arc/button/button"
import styles from "./account.module.css"
import { ownershipFix } from "./ownership"

/**
 * A stock whose holdings don't add up, as one attention row: what doesn't add up, what waits on it, and the
 * owner's one answer. The answer opens a line saying what it does before anything is sent. While an order the app
 * didn't place is open at the broker the engine can't settle holdings, so the row says what has to happen first.
 */
export function OwnershipRow({
  incident,
  account,
  blocked,
  onResolved,
}: {
  incident: OwnershipIncident
  account: AccountOverview
  blocked: boolean
  onResolved: () => void
}) {
  const [confirming, setConfirming] = useState(false)
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const fix = ownershipFix(incident, account.positions.find((p) => p.symbol === incident.symbol), account.account_id)

  async function settle() {
    setSending(true)
    setError(null)
    const result = await window.copytrading.act.resolveOwnership({ account_id: account.account_id, resolution: fix.request })
    setSending(false)
    if (result.ok) onResolved()
    else setError(`${account.account_id}: ${result.error}`)
  }

  return (
    <Alert tone="warning" title={fix.headline}>
      <p className={styles.alertText}>{fix.detail}</p>
      {blocked ? (
        <p className={styles.alertText}>First, the open order in Alpaca has to fill or be cancelled.</p>
      ) : confirming ? (
        <>
          <p className={styles.alertStrong}>{fix.confirmation}</p>
          {error && (
            <p role="alert" className={styles.noteDanger}>
              {error}
            </p>
          )}
          <div className={styles.alertActions}>
            <Button type="button" size="sm" variant="secondary" disabled={sending} onClick={() => setConfirming(false)}>
              Not now
            </Button>
            <Button type="button" size="sm" variant="secondary" loading={sending} onClick={settle}>
              {fix.confirm}
            </Button>
          </div>
        </>
      ) : (
        <div className={styles.alertActions}>
          <Button type="button" size="sm" variant="secondary" onClick={() => setConfirming(true)}>
            {fix.action}
          </Button>
        </div>
      )}
    </Alert>
  )
}
