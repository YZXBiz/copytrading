import { useState } from "react"
import type { AccountPolicy, RecoveryPreference, SetupView } from "../../../shared/contract"
import { Button } from "@/components/arc/button/button"
import { Drawer, DrawerContent } from "@/components/arc/drawer/drawer"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { NumberField } from "@/components/arc/number-field/number-field"
import SegmentedControl from "@/components/arc/segmented-control/segmented-control"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import { Switch } from "@/components/arc/switch/switch"
import { useResult } from "@/lib/use-result"
import { BEHAVIORS, POSITION_LIMITS, RECOVERY_HINT, RECOVERY_TITLE, TIMING_LIMITS, type LimitsDraft, draftFromPolicy, draftNumber, limitErrors, limitsChanged, numberDraft, policyFromDraft, setFlag, withLimits } from "./limits"
import { RegionNote } from "./RegionNote"
import styles from "./sheet.module.css"

function Form({ setup, accountId, policy, onClose }: { setup: SetupView; accountId: string; policy: AccountPolicy; onClose: (saved: boolean) => void }) {
  const [draft, setDraft] = useState<LimitsDraft>(() => draftFromPolicy(policy))
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const errors = limitErrors(draft)
  const changed = limitsChanged(draft, policy)

  async function save() {
    setSaving(true)
    setError(null)
    // The engine takes the whole setup; only this account's limits differ from the saved one. Main asks the owner first.
    const result = await window.copytrading.act.updateAccountLimits({ configuration: withLimits(setup.configuration, accountId, policyFromDraft(draft, policy)) })
    setSaving(false)
    if (result.ok) onClose(true)
    else if (!result.cancelled) setError(`${accountId}: ${result.error}`)
  }

  // Steppers and scrubbing move a number; the draft stays the decimal text the checks and the save read, and a field that was not touched keeps its saved text.
  const field = (key: Extract<keyof LimitsDraft, keyof typeof errors>, title: string, hint: string, step: number) => (
    <div key={key} className={styles.field}>
      <NumberField
        id={`limit-${key}`}
        label={title}
        min={0}
        step={step}
        prefix={key.endsWith("_usd") ? "$" : undefined}
        suffix={key.endsWith("_pct") ? "%" : undefined}
        scrub
        formatOptions={{ useGrouping: false, maximumFractionDigits: 6 }}
        value={draftNumber(draft[key]) ?? undefined}
        description={errors[key] ? undefined : hint}
        onValueChange={(value) => setDraft((d) => (draftNumber(d[key]) === value ? d : { ...d, [key]: numberDraft(value) }))}
      />
      {errors[key] && (
        <p role="alert" className={styles.problem}>
          {errors[key]}
        </p>
      )}
    </div>
  )

  return (
    <>
      <div className={styles.sections}>
        <fieldset className={styles.group}>
          <legend>Position limits</legend>
          {POSITION_LIMITS.map((f) => field(f.key, f.title, f.hint, f.step))}
        </fieldset>
        <fieldset className={styles.group}>
          <legend>Timing</legend>
          {TIMING_LIMITS.map((f) => field(f.key, f.title, f.hint, f.step))}
        </fieldset>
        <fieldset className={styles.group}>
          <legend>Behavior</legend>
          {BEHAVIORS.map((f) => (
            <div key={f.key} className={styles.switchRow}>
              <div>
                <span id={`behavior-${f.key}`} className={styles.switchTitle}>
                  {f.title}
                </span>
                <p id={`behavior-${f.key}-hint`} className={styles.hint}>
                  {f.hint}
                </p>
              </div>
              <Switch aria-labelledby={`behavior-${f.key}`} aria-describedby={`behavior-${f.key}-hint`} checked={draft[f.key]} onCheckedChange={(on) => setDraft((d) => setFlag(d, f.key, on))} />
            </div>
          ))}
          <div className={styles.field}>
            <span className={styles.fieldLabel}>After a restart</span>
            <SegmentedControl
              label="After a restart"
              value={draft.recovery_preference}
              onValueChange={(next) => setDraft((d) => ({ ...d, recovery_preference: next as RecoveryPreference }))}
              options={(["manual", "automatic"] as const).map((p) => ({ value: p, label: RECOVERY_TITLE[p] }))}
            />
            <p className={styles.hint}>{RECOVERY_HINT[draft.recovery_preference]}</p>
          </div>
          <p className={styles.hint}>Only shares CopyTrading bought are ever sold. Your own shares are never touched.</p>
        </fieldset>
        {error && (
          <p role="alert" className={styles.problem}>
            {error}
          </p>
        )}
      </div>
      <div className={styles.footer}>
        <Button type="button" variant="secondary" disabled={saving} onClick={() => onClose(false)}>
          Cancel
        </Button>
        <Button type="button" loading={saving} disabled={!changed || Object.keys(errors).length > 0} onClick={save}>
          Save limits
        </Button>
      </div>
    </>
  )
}

/**
 * The account's limits, with the fields and hints of the SwiftUI account editor. Saving gives copying the new limits
 * at once (after the main process lists each change for the owner) and saves them in the setup.
 */
export function LimitsSheet({ accountId, onClose }: { accountId: string; onClose: (saved: boolean) => void }) {
  const setup = useResult(() => window.copytrading.read.getSetup(), accountId)
  const policy = setup.status === "ready" ? setup.data?.configuration.accounts.find((a) => a.id === accountId)?.policy : undefined
  return (
    <Drawer open onOpenChange={(open) => !open && onClose(false)}>
      <DrawerContent title={`Limits for ${accountId}`} description="Changes apply from the next order." className={styles.sheet}>
        {setup.status === "loading" && <Skeleton label="Loading limits" lines={6} />}
        {setup.status === "error" && <RegionNote title="The saved setup did not load" message={setup.error} onRetry={setup.retry} />}
        {setup.status === "ready" && !policy && <EmptyState title="No saved limits for this account" description="Save the account in Connections first." />}
        {setup.status === "ready" && setup.data && policy && <Form setup={setup.data} accountId={accountId} policy={policy} onClose={onClose} />}
      </DrawerContent>
    </Drawer>
  )
}
