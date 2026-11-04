import { CircleAlertIcon, OctagonXIcon } from "lucide-react"
import type { AccountOverview, TradingStatus } from "../../../shared/contract"
import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert"
import { STOPPED_BODY, accountCopying, stoppedTitle } from "./copying"
import { OwnershipRow } from "./OwnershipRow"
import { reasonText } from "@/lib/reasons"

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
        <Alert variant="destructive">
          <OctagonXIcon aria-hidden />
          <AlertTitle>{stoppedTitle(account.account_id)}</AlertTitle>
          <AlertDescription>
            {state.detail && <p className="text-foreground">{state.detail}.</p>}
            <p>{STOPPED_BODY}</p>
          </AlertDescription>
        </Alert>
      )}
      {risk && (
        <Alert variant="warning">
          <CircleAlertIcon aria-hidden />
          <AlertTitle>Risk valuation: {reasonText(risk)}</AlertTitle>
        </Alert>
      )}
      {activity && (
        <Alert variant="warning">
          <CircleAlertIcon aria-hidden />
          <AlertTitle>
            {activity === "unresolved_account_order" ? "An order in Alpaca that CopyTrading didn't place is still open" : reasonText(activity)}
          </AlertTitle>
          <AlertDescription>
            {activity === "unresolved_account_order"
              ? "Let it fill or cancel it in Alpaca. Until it's gone, CopyTrading can't settle holdings."
              : "CopyTrading checks again on the next sync."}
          </AlertDescription>
        </Alert>
      )}
      {incidents.map((incident) => (
        <OwnershipRow key={incident.incident_id} incident={incident} account={account} blocked={activity !== null} onResolved={onResolved} />
      ))}
      {unlisted.length > 0 && (
        <Alert variant="destructive">
          <CircleAlertIcon aria-hidden />
          <AlertTitle>Unresolved incidents: {unlisted.join(", ")}</AlertTitle>
        </Alert>
      )}
    </>
  )
}
