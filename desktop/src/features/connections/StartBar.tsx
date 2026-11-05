import { PauseIcon } from "@/components/icons/PauseIcon"
import { PlayIcon } from "@/components/icons/PlayIcon"
import { RefreshIcon } from "@/components/icons/RefreshIcon"
import { Button } from "@/components/arc/button/button"
import { SaveBar } from "@/components/arc/blocks/settings-page/settings-page"
import type { Derived } from "./derive"
import { applyChanges, discard, reload, startCopying, type SetupState } from "./setup-store"
import { canApplyChanges, canStartCopying, startStatus } from "./start-status"
import styles from "./connections.module.css"

/** How far the setup has come and the one button that checks every connection and starts, or applies a change while copying. */
export function StartControls({ s, derived }: { s: SetupState; derived: Derived }) {
  const trading = s.load.status === "ready" ? s.load.data.trading : null
  const status = startStatus({ start: s.start, progress: derived.progress, trading, isCopying: derived.copying, hasSaved: derived.hasSaved, hasUnsaved: derived.hasUnsaved })
  const busy = status.tone === "working" && s.start.phase !== "idle"
  const canDiscard = derived.hasSaved && derived.hasUnsaved && !busy
  return (
    <>
      <div className={styles.barText} aria-live="polite">
        <strong>{status.text}</strong>
        {status.detail && <span>{status.detail}</span>}
      </div>
      <div className={styles.barButtons}>
        {canDiscard && (
          <Button type="button" size="sm" variant="ghost" onClick={() => void discard()}>
            Discard changes
          </Button>
        )}
        {derived.copying ? (
          <>
            <Button type="button" size="sm" variant="secondary" disabled={busy} onClick={() => void window.copytrading.act.pauseTrading().then(() => reload({ keepDraft: true }))}>
              <PauseIcon width={16} height={16} aria-hidden="true" />
              Pause copying
            </Button>
            <Button type="button" size="sm" loading={busy} disabled={!canApplyChanges({ start: s.start, progress: derived.progress, isCopying: true, hasUnsaved: derived.hasUnsaved })} onClick={() => void applyChanges()}>
              <RefreshIcon width={16} height={16} aria-hidden="true" />
              Apply changes
            </Button>
          </>
        ) : (
          <Button type="button" size="sm" loading={busy} disabled={!canStartCopying({ start: s.start, progress: derived.progress, trading })} onClick={() => void startCopying()}>
            <PlayIcon width={16} height={16} aria-hidden="true" />
            Start copying
          </Button>
        )}
      </div>
    </>
  )
}

/** The same controls, floating over the Settings page while there is something to save or start. */
export function ConnectionsBar({ s, derived }: { s: SetupState; derived: Derived }) {
  return (
    <SaveBar label="Setup changes">
      <StartControls s={s} derived={derived} />
    </SaveBar>
  )
}
