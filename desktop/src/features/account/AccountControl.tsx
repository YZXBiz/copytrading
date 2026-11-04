import { useState } from "react"
import type { AccountOverview, TradingStatus } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
import { CirclePlayIcon } from "@/reui/icons/animated/duotone/circle-play"
import { SquareInCircleIcon } from "@/reui/icons/animated/duotone/square-in-circle"
import type { Loaded } from "@/lib/use-result"
import { accountCopying, resumeBlocked } from "./copying"

type Status = Loaded<TradingStatus> & { retry: () => void }

/**
 * Whether CopyTrading copies into this account, and its one Stop or Start Copying. Starting here only turns this
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

/** Stop Copying while copying, else Start Copying (primary unless `variant` says otherwise). */
export function ControlButton({ control, variant }: { control: AccountControl; variant?: "outline" }) {
  const { copying, pending, blocked, status } = control
  return copying ? (
    <Button size="sm" type="button" variant="outline" disabled={pending} onClick={() => control.control("pause")} title="No new buys in this account. Sells of what it copied still follow the guru.">
      {pending ? <Spinner aria-label="Saving account command" /> : <SquareInCircleIcon aria-hidden className="size-4" />} Stop Copying
    </Button>
  ) : (
    <Button size="sm" type="button" variant={variant} disabled={pending || blocked !== null || status.status !== "ready"} onClick={() => control.control("resume")} title="Copy the guru's buys and sells into this account.">
      {pending ? <Spinner aria-label="Saving account command" /> : <CirclePlayIcon aria-hidden className="size-4" />} Start Copying
    </Button>
  )
}

/** Why Start is off, a state that did not load, a command that failed, and that the limits were just saved. */
export function ControlNotes({ control, saved }: { control: AccountControl; saved: boolean }) {
  const { blocked, error, status } = control
  if (!blocked && !error && !saved && status.status !== "error") return null
  return (
    <div className="flex flex-col gap-2">
      {blocked && <p className="text-muted-foreground text-xs">{blocked}</p>}
      {status.status === "error" && (
        <p role="alert" className="text-destructive flex items-center gap-2 text-xs">
          Whether copying runs did not load: {status.error}
          <Button type="button" size="xs" variant="outline" onClick={status.retry}>
            Retry
          </Button>
        </p>
      )}
      {error && (
        <p role="alert" className="text-destructive text-xs">
          {error}
        </p>
      )}
      {saved && (
        <Badge variant="success-light" className="self-start">
          Saved for the next order
        </Badge>
      )}
    </div>
  )
}
