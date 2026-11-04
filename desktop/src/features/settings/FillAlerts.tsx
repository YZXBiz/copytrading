import { useState } from "react"
import { RegionError } from "@/components/region-error"
import { Skeleton } from "@/components/ui/skeleton"
import { Switch } from "@/components/ui/switch"
import { useResult } from "@/lib/use-result"
import { Note, type NoteState } from "./Note"
import { SettingsRow } from "./SettingsRow"
import { SettingsSection } from "./SettingsSection"

/** "Tell me when a trade fills": a macOS notification as each copied order goes out and fills. Accounts stopping is always announced. */
export function FillAlerts() {
  const on = useResult(() => window.copytrading.read.getFillAlerts(), "fill-alerts")
  const [note, setNote] = useState<NoteState | null>(null)
  // What main said after the owner's last change; the read above is only the first answer.
  const [changed, setChanged] = useState<boolean | null>(null)

  if (on.status === "loading") return <Skeleton className="h-16 w-full" />
  if (on.status === "error") return <RegionError title="Notification setting did not load" message={on.error} onRetry={on.retry} />

  async function change(next: boolean) {
    const result = await window.copytrading.act.setFillAlerts({ on: next })
    if (result.ok) setChanged(result.value)
    setNote(result.ok ? null : { kind: "problem", text: result.error })
  }

  return (
    <>
      {note && <Note note={note} />}
      <SettingsSection title="While Copying">
        <SettingsRow title="Tell me when a trade fills">
          <Switch aria-label="Tell me when a trade fills" checked={changed ?? on.data} onCheckedChange={(next) => void change(next)} />
        </SettingsRow>
      </SettingsSection>
    </>
  )
}
