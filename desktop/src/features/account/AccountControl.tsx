import { useState } from "react"
import type { AccountOverview, TradingStatus } from "../../../shared/contract"
import { Badge } from "@/components/arc/badge/badge"
import { Button } from "@/components/arc/button/button"
import { Tooltip } from "@/components/arc/tooltip/tooltip"
import type { Loaded } from "@/lib/use-result"
import styles from "./account.module.css"
import { accountCopying, resumeBlocked } from "./copying"

type Status = Loaded<TradingStatus> & { retry: () => void }

/**
 * Whether CopyTrading copies into this account, and its one Stop or Start copying. Starting here only turns this
 * account's buys back on (`control_account`); starting copying itself is the setup's Start.
 */
export function useAccountControl(account: AccountOverview, status: Status, onChanged: () => void) {
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const current = status.status === "ready" ? status.data : null
  const state = accountCopying(account, current)
  const copying = state.word === "copying"
  // Until the engine has said whether copying runs, Start has nothing true to say about why it is off.
  const blocked = copying || status.status !== "ready" ? null : resumeBlocked(account, current)

  async function control(action: "pause" | "resume") {
    setPending(true)
    setError(null)
    const result = await window.copytrading.act.controlAccount({
      command: { command_id: crypto.randomUUID(), account_id: account.account_id, action },
    })
    setPending(false)
    if (result.ok) onChanged()
    else if (!result.cancelled) setError(`${account.account_id}: ${result.error}`)
  }

  return { state, copying, blocked, pending, error, status, control }
}

export type AccountControl = ReturnType<typeof useAccountControl>

/** The page's one primary action: Stop copying while copying, else Start copying. */
export function ControlButton({ control }: { control: AccountControl }) {
  const { copying, pending, blocked, status } = control
  return copying ? (
    <Tooltip content="No new buys in this account. Sells of what it copied still follow the guru." side="bottom">
      <Button type="button" loading={pending} onClick={() => control.control("pause")}>
        Stop copying
      </Button>
    </Tooltip>
  ) : (
    <Tooltip content="Copy the guru's buys and sells into this account." side="bottom">
      <Button type="button" loading={pending} disabled={blocked !== null || status.status !== "ready"} onClick={() => control.control("resume")}>
        Start copying
      </Button>
    </Tooltip>
  )
}

/** Why Start is off, a state that did not load, a command that failed, and that the limits were just saved. */
export function ControlNotes({ control, saved }: { control: AccountControl; saved: boolean }) {
  const { blocked, error, status } = control
  if (!blocked && !error && !saved && status.status !== "error") return null
  return (
    <div className={styles.notes}>
      {blocked && <p className={styles.note}>{blocked}</p>}
      {status.status === "error" && (
        <p role="alert" className={styles.noteDanger}>
          Whether copying runs did not load: {status.error}
          <Button type="button" size="sm" variant="secondary" onClick={status.retry}>
            Retry
          </Button>
        </p>
      )}
      {error && (
        <p role="alert" className={styles.noteDanger}>
          {error}
        </p>
      )}
      {saved && (
        <span role="status">
          <Badge tone="success">Saved for the next order</Badge>
        </span>
      )}
    </div>
  )
}
