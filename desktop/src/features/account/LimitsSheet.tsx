import { useState } from "react"
import { SlidersHorizontalIcon } from "@/components/icons/SlidersHorizontalIcon"
import type { AccountPolicy, RecoveryPreference, SetupView } from "../../../shared/contract"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Empty, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { Field, FieldContent, FieldDescription, FieldError, FieldGroup, FieldSeparator, FieldSet, FieldLegend, FieldTitle } from "@/components/ui/field"
import { NumberField, NumberFieldDecrement, NumberFieldGroup, NumberFieldIncrement, NumberFieldInput, NumberFieldScrubArea } from "@/components/reui/number-field"
import { Sheet, SheetContent, SheetDescription, SheetFooter, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { Skeleton } from "@/components/ui/skeleton"
import { Spinner } from "@/components/ui/spinner"
import { Switch } from "@/components/ui/switch"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { useResult } from "@/lib/use-result"
import { BEHAVIORS, POSITION_LIMITS, RECOVERY_HINT, RECOVERY_TITLE, TIMING_LIMITS, type LimitsDraft, draftFromPolicy, draftNumber, limitErrors, limitsChanged, numberDraft, policyFromDraft, setFlag, withLimits } from "./limits"

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
    <Field key={key} data-invalid={errors[key] ? true : undefined}>
      <NumberField
        id={`limit-${key}`}
        min={0}
        step={step}
        format={{ useGrouping: false, maximumFractionDigits: 6 }}
        value={draftNumber(draft[key])}
        onValueChange={(value) => setDraft((d) => (draftNumber(d[key]) === value ? d : { ...d, [key]: numberDraft(value) }))}
      >
        <NumberFieldScrubArea label={title} />
        <NumberFieldGroup aria-invalid={errors[key] ? true : undefined}>
          <NumberFieldDecrement aria-label={`Lower ${title}`} />
          <NumberFieldInput inputMode="decimal" />
          <NumberFieldIncrement aria-label={`Raise ${title}`} />
        </NumberFieldGroup>
      </NumberField>
      {errors[key] ? <FieldError>{errors[key]}</FieldError> : <FieldDescription>{hint}</FieldDescription>}
    </Field>
  )

  return (
    <>
      <div className="flex-1 overflow-y-auto px-4">
        <FieldGroup className="gap-6">
          <FieldSet className="gap-4">
            <FieldLegend variant="label">Position limits (USD)</FieldLegend>
            {POSITION_LIMITS.map((f) => field(f.key, f.title, f.hint, f.step))}
          </FieldSet>
          <FieldSeparator />
          <FieldSet className="gap-4">
            <FieldLegend variant="label">Timing</FieldLegend>
            {TIMING_LIMITS.map((f) => field(f.key, f.title, f.hint, f.step))}
          </FieldSet>
          <FieldSeparator />
          <FieldSet className="gap-4">
            <FieldLegend variant="label">Behavior</FieldLegend>
            {BEHAVIORS.map((f) => (
              <Field key={f.key} orientation="horizontal">
                <FieldContent>
                  <FieldTitle>{f.title}</FieldTitle>
                  <FieldDescription>{f.hint}</FieldDescription>
                </FieldContent>
                <Switch size="sm" aria-label={f.title} checked={draft[f.key]} onCheckedChange={(on) => setDraft((d) => setFlag(d, f.key, on))} />
              </Field>
            ))}
            <Field orientation="horizontal">
              <FieldContent>
                <FieldTitle>After a restart</FieldTitle>
                <FieldDescription>{RECOVERY_HINT[draft.recovery_preference]}</FieldDescription>
              </FieldContent>
              <ToggleGroup aria-label="After a restart" variant="outline" size="sm" value={[draft.recovery_preference]} onValueChange={(next) => next[0] && setDraft((d) => ({ ...d, recovery_preference: next[0] as RecoveryPreference }))}>
                {(["manual", "automatic"] as const).map((p) => (
                  <ToggleGroupItem key={p} value={p}>
                    {RECOVERY_TITLE[p]}
                  </ToggleGroupItem>
                ))}
              </ToggleGroup>
            </Field>
            <FieldDescription>Only shares CopyTrading bought are ever sold. Your own shares are never touched.</FieldDescription>
          </FieldSet>
          {error && (
            <p role="alert" className="text-destructive text-sm">
              {error}
            </p>
          )}
        </FieldGroup>
      </div>
      <SheetFooter className="flex-row items-center justify-end">
        {saving && <Spinner aria-label="Saving" />}
        <Button size="sm" type="button" variant="outline" disabled={saving} onClick={() => onClose(false)}>
          Cancel
        </Button>
        <Button size="sm" type="button" disabled={saving || !changed || Object.keys(errors).length > 0} onClick={save}>
          Save Limits
        </Button>
      </SheetFooter>
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
    <Sheet open onOpenChange={(open) => !open && onClose(false)}>
      <SheetContent className="w-full sm:max-w-md">
        <SheetHeader>
          <SheetTitle>Limits for {accountId}</SheetTitle>
          <SheetDescription>Changes apply from the next order.</SheetDescription>
        </SheetHeader>
        {setup.status === "loading" && (
          <div role="status" aria-label="Loading limits" className="flex flex-col gap-4 px-4">
            {Array.from({ length: 6 }, (_, i) => (
              <Skeleton key={i} className="h-9 w-full" />
            ))}
          </div>
        )}
        {setup.status === "error" && (
          <div className="px-4">
            <RegionError title="The saved setup did not load" message={setup.error} onRetry={setup.retry} />
          </div>
        )}
        {setup.status === "ready" && !policy && (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <SlidersHorizontalIcon />
              </EmptyMedia>
              <EmptyTitle>No saved limits for this account</EmptyTitle>
              <EmptyDescription>Save the account in Connections first.</EmptyDescription>
            </EmptyHeader>
          </Empty>
        )}
        {setup.status === "ready" && setup.data && policy && <Form setup={setup.data} accountId={accountId} policy={policy} onClose={onClose} />}
      </SheetContent>
    </Sheet>
  )
}
