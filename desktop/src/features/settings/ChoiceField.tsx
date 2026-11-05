import { useState } from "react"
import type { Result } from "../../../shared/contract"
import { Button } from "@/components/arc/button/button"
import SegmentedControl from "@/components/arc/segmented-control/segmented-control"
import { useResult } from "@/lib/use-result"
import { Note, type NoteState } from "./Note"
import { SettingsRow } from "./SettingsRow"
import { SectionSkeleton } from "./SettingsSection"

/** A saved choice among a few words (Theme, Menu bar): main saves it and applies it live, and the page shows what main says it kept. */
export function ChoiceField<T extends string>({ title, items, read, write }: { title: string; items: { value: T; label: string }[]; read: () => Promise<Result<T>>; write: (value: T) => Promise<Result<T>> }) {
  const saved = useResult(read, `choice:${title}`)
  const [chosen, setChosen] = useState<T | null>(null)
  const [note, setNote] = useState<NoteState | null>(null)

  if (saved.status === "loading") return <SettingsRow title={title}><SectionSkeleton rows={1} label={`Loading ${title.toLowerCase()}`} /></SettingsRow>
  if (saved.status === "error")
    return (
      <SettingsRow title={title} description={saved.error} tone="caution">
        <Button type="button" size="sm" variant="secondary" onClick={saved.retry}>
          Try again
        </Button>
      </SettingsRow>
    )

  async function change(next: string) {
    setChosen(next as T)
    const result = await write(next as T)
    setChosen(result.ok ? result.value : null)
    setNote(result.ok ? null : { kind: "problem", text: result.error })
  }

  return (
    <>
      {note && <Note note={note} />}
      <SettingsRow title={title}>
        <SegmentedControl label={title} options={items} value={chosen ?? saved.data} onValueChange={(next) => void change(next)} />
      </SettingsRow>
    </>
  )
}
