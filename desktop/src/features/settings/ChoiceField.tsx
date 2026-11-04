import { useState } from "react"
import type { Result } from "../../../shared/contract"
import { Button } from "@/components/ui/button"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Skeleton } from "@/components/ui/skeleton"
import { useResult } from "@/lib/use-result"
import { Note, type NoteState } from "./Note"
import { SettingsRow } from "./SettingsRow"

/** A saved choice among a few words (Theme, Menu bar): main saves it and applies it live, and the page shows what main says it kept. */
export function ChoiceField<T extends string>({ title, items, read, write }: { title: string; items: { value: T; label: string }[]; read: () => Promise<Result<T>>; write: (value: T) => Promise<Result<T>> }) {
  const saved = useResult(read, `choice:${title}`)
  const [chosen, setChosen] = useState<T | null>(null)
  const [note, setNote] = useState<NoteState | null>(null)

  if (saved.status === "loading")
    return (
      <SettingsRow title={title}>
        <Skeleton role="status" aria-label="Loading" className="h-7 w-44" />
      </SettingsRow>
    )
  if (saved.status === "error")
    return (
      <SettingsRow title={title} description={saved.error} tone="caution">
        <Button type="button" size="sm" variant="outline" onClick={saved.retry}>
          Try again
        </Button>
      </SettingsRow>
    )

  async function change(next: T) {
    setChosen(next)
    const result = await write(next)
    setChosen(result.ok ? result.value : null)
    setNote(result.ok ? null : { kind: "problem", text: result.error })
  }

  return (
    <>
      {note && <Note note={note} />}
      <SettingsRow title={title}>
        <Select value={chosen ?? saved.data} items={items} onValueChange={(next) => next && void change(next as T)}>
          <SelectTrigger size="sm" aria-label={title} className="w-44">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {items.map((item) => (
              <SelectItem key={item.value} value={item.value}>
                {item.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </SettingsRow>
    </>
  )
}
