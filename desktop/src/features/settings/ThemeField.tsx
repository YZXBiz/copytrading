import { type Theme, THEMES } from "../../../shared/contract"
import { Button } from "@/components/ui/button"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useResult } from "@/lib/use-result"
import { useState } from "react"
import { Note, type NoteState } from "./Note"
import { SettingsRow } from "./SettingsRow"
import { Skeleton } from "@/components/ui/skeleton"

const TITLE: Record<Theme, string> = { dark: "Dark", light: "Light", system: "System" }
const ITEMS = THEMES.map((value) => ({ value, label: TITLE[value] }))

/** Dark, Light or System. Main saves the choice and applies it to the window, so the page and the sidebar's vibrancy change together. */
export function ThemeField() {
  const saved = useResult(() => window.copytrading.read.getTheme(), "theme")
  const [chosen, setChosen] = useState<Theme | null>(null)
  const [note, setNote] = useState<NoteState | null>(null)

  if (saved.status === "loading")
    return (
      <SettingsRow title="Theme">
        <Skeleton role="status" aria-label="Loading" className="h-7 w-28" />
      </SettingsRow>
    )
  if (saved.status === "error")
    return (
      <SettingsRow title="Theme" description={saved.error} tone="caution">
        <Button type="button" size="sm" variant="outline" onClick={saved.retry}>
          Try again
        </Button>
      </SettingsRow>
    )

  async function change(next: Theme) {
    setChosen(next)
    const result = await window.copytrading.act.setTheme({ theme: next })
    setChosen(result.ok ? result.value : null)
    setNote(result.ok ? null : { kind: "problem", text: result.error })
  }

  return (
    <>
      {note && <Note note={note} />}
      <SettingsRow title="Theme">
        <Select value={chosen ?? saved.data} items={ITEMS} onValueChange={(next) => next && void change(next as Theme)}>
          <SelectTrigger size="sm" aria-label="Theme" className="w-28">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {ITEMS.map((item) => (
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
