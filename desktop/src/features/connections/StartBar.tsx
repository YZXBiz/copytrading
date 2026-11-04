import { CircleAlertIcon, CircleCheckIcon, InfoIcon, PauseIcon, PlayIcon, RefreshCwIcon } from "lucide-react"
import { Alert, AlertAction, AlertDescription, AlertTitle } from "@/components/reui/alert"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
import { CheckResults } from "./CheckResults"
import type { Derived } from "./derive"
import { applyChanges, discard, reload, startCopying, type SetupState } from "./setup-store"
import { canApplyChanges, canStartCopying, startStatus } from "./start-status"

const VARIANT = { working: "default", positive: "success", caution: "warning", neutral: "default" } as const

/** The foot of Connections: how far the setup has come and the one button that checks every connection and starts, or applies a change while copying. */
export function StartBar({ s, derived }: { s: SetupState; derived: Derived }) {
  const trading = s.load.status === "ready" ? s.load.data.trading : null
  const status = startStatus({ start: s.start, progress: derived.progress, trading, isCopying: derived.copying, hasSaved: derived.hasSaved, hasUnsaved: derived.hasUnsaved })
  const busy = status.tone === "working" && s.start.phase !== "idle"
  const canDiscard = derived.hasSaved && derived.hasUnsaved && !busy
  const Icon = status.tone === "positive" ? CircleCheckIcon : status.tone === "caution" ? CircleAlertIcon : InfoIcon
  return (
    <div className="flex flex-col gap-4">
      <Alert variant={VARIANT[status.tone]} aria-live="polite">
        {status.tone === "working" ? <Spinner aria-hidden /> : <Icon aria-hidden />}
        <AlertTitle>{status.text}</AlertTitle>
        {status.detail && <AlertDescription>{status.detail}</AlertDescription>}
        <AlertAction>
          {canDiscard && (
            <Button type="button" size="sm" variant="ghost" onClick={() => void discard()}>
              Discard changes
            </Button>
          )}
          {derived.copying ? (
            <>
              <Button
                type="button"
                size="sm"
                variant="outline"
                disabled={busy}
                onClick={() => void window.copytrading.act.pauseTrading().then(() => reload({ keepDraft: true }))}
              >
                <PauseIcon aria-hidden /> Pause copying
              </Button>
              <Button type="button" size="sm" disabled={!canApplyChanges({ start: s.start, progress: derived.progress, isCopying: true, hasUnsaved: derived.hasUnsaved })} onClick={() => void applyChanges()}>
                <RefreshCwIcon aria-hidden /> Apply changes
              </Button>
            </>
          ) : (
            <Button type="button" size="sm" disabled={!canStartCopying({ start: s.start, progress: derived.progress, trading })} onClick={() => void startCopying()}>
              <PlayIcon aria-hidden /> Start copying
            </Button>
          )}
        </AlertAction>
      </Alert>
      {s.start.phase === "failed" && s.start.report && <CheckResults report={s.start.report} modelName={s.draft.model} />}
    </div>
  )
}
