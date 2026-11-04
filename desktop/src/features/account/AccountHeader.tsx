import { useState } from "react"
import { PauseIcon } from "lucide-react"
import type { AccountOverview, TradingStatus } from "../../../shared/contract"
import { Meta } from "@/components/meta"
import { Badge } from "@/components/reui/badge"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
import { CirclePlayIcon } from "@/reui/icons/animated/outline/circle-play"
import type { Loaded } from "@/lib/use-result"
import { COPYING_TITLE, accountCopying, badgeVariant, isWarning, resumeBlocked } from "./copying"

/**
 * The account's name, its mode, whether CopyTrading copies into it, and its one Stop or Resume Copying.
 * Resuming only turns this account's buys back on (`control_account`); starting copying itself is the setup's Start.
 */
export function AccountHeader({
  account,
  guru,
  status,
  saved,
  onChanged,
}: {
  account: AccountOverview
  guru: string | null
  status: Loaded<TradingStatus> & { retry: () => void }
  /** The limits were just saved: say they apply from the next order. */
  saved: boolean
  onChanged: () => void
}) {
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const current = status.status === "ready" ? status.data : null
  const state = accountCopying(account, current)
  const copying = state.word === "copying"
  // Until the engine has said whether copying runs, Resume has nothing true to say about why it is off.
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

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="flex min-w-0 flex-col gap-1.5">
          <h1 className="truncate text-2xl font-semibold tracking-tight">{account.account_id}</h1>
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant="outline">{account.environment === "paper" ? "Paper" : "Live"}</Badge>
            <Badge variant={badgeVariant(state)}>{COPYING_TITLE[state.word]}</Badge>
            {state.detail && isWarning(state) && <span className="text-muted-foreground text-xs">{state.detail}</span>}
            {guru && <span className="text-muted-foreground text-xs">Copies {guru}</span>}
          </div>
        </div>
        <div className="flex items-center gap-2">
          {pending && <Spinner aria-label="Saving account command" />}
          {copying ? (
            <Button type="button" variant="outline" disabled={pending} onClick={() => control("pause")} title="No new buys in this account. Sells of what it copied still follow the guru.">
              <PauseIcon aria-hidden /> Stop Copying
            </Button>
          ) : (
            <Button type="button" disabled={pending || blocked !== null || status.status !== "ready"} onClick={() => control("resume")} title="Copy the guru's buys and sells into this account.">
              <CirclePlayIcon aria-hidden className="size-4" /> Resume Copying
            </Button>
          )}
        </div>
      </div>
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
          <Meta items={["Saved", "applies to the next order"]} />
        </Badge>
      )}
    </div>
  )
}
