import { useState } from "react"
import { CircleAlertIcon } from "lucide-react"
import type { OwnershipIncident, AccountOverview } from "../../../shared/contract"
import { Alert, AlertAction, AlertDescription, AlertTitle } from "@/components/reui/alert"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
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
    <Alert variant="warning">
      <CircleAlertIcon aria-hidden />
      <AlertTitle>{fix.headline}</AlertTitle>
      <AlertDescription>
        <p>{fix.detail}</p>
        {blocked ? (
          <p>First, the open order in Alpaca has to fill or be cancelled.</p>
        ) : confirming ? (
          <>
            <p className="text-foreground">{fix.confirmation}</p>
            {error && (
              <p role="alert" className="text-destructive">
                {error}
              </p>
            )}
          </>
        ) : null}
      </AlertDescription>
      {!blocked && (
        <AlertAction>
          {confirming ? (
            <>
              {sending && <Spinner aria-label="Sending" />}
              <Button type="button" size="xs" variant="outline" disabled={sending} onClick={() => setConfirming(false)}>
                Not Now
              </Button>
              <Button type="button" size="xs" disabled={sending} onClick={settle}>
                {fix.confirm}
              </Button>
            </>
          ) : (
            <Button type="button" size="xs" variant="outline" onClick={() => setConfirming(true)}>
              {fix.action}
            </Button>
          )}
        </AlertAction>
      )}
    </Alert>
  )
}
