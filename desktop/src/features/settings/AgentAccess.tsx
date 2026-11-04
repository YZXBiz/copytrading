import { useState } from "react"
import type { AgentAccess as Access, AgentAccessState } from "../../../shared/contract"
import { RegionError } from "@/components/region-error"
import { Badge } from "@/components/reui/badge"
import { Skeleton } from "@/components/ui/skeleton"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { useResult } from "@/lib/use-result"
import { Note, type NoteState } from "./Note"
import { SettingsRow } from "./SettingsRow"
import { SettingsSection } from "./SettingsSection"

// AgentAccessPage.swift: how far agents such as Claude Code may go through the copytrading command and MCP server.
const CHOICES: { value: Access; label: string; detail: string }[] = [
  { value: "off", label: "Nothing", detail: "Agents cannot reach CopyTrading." },
  { value: "read_pause", label: "Read and pause", detail: "Agents can read your accounts and pause copying. Pausing always works." },
  { value: "propose", label: "Read, pause, and ask for approval", detail: "Anything that could trade waits for your approval here." },
]

/** Whether agents may connect and how far; changing it asks the owner first (main shows the dialog). */
export function AgentAccess() {
  const state = useResult(() => window.copytrading.read.getAgentAccess(), "agent-access")
  const [note, setNote] = useState<NoteState | null>(null)
  const [busy, setBusy] = useState(false)
  // What main said after the owner's last change; the read above is only the first answer.
  const [changed, setChanged] = useState<AgentAccessState | null>(null)

  if (state.status === "loading") return <Skeleton className="h-28 w-full" />
  if (state.status === "error") return <RegionError title="Agent access did not load" message={state.error} onRetry={state.retry} />
  const { access, listening, problem } = changed ?? state.data
  const chosen = CHOICES.find((c) => c.value === access)!

  async function choose(next: Access) {
    setBusy(true)
    const result = await window.copytrading.act.setAgentAccess({ access: next })
    setBusy(false)
    if (result.ok) setChanged(result.value)
    // A Cancel in the dialog changes nothing and says nothing.
    setNote(result.ok || result.cancelled ? null : { kind: "problem", text: result.error })
  }

  return (
    <>
      {note && <Note note={note} />}
      <SettingsSection title="Allow Agents To" hint="Agents such as Claude Code connect through the copytrading command or MCP server while the app runs.">
        <SettingsRow title="Access" description={chosen.detail}>
          <ToggleGroup aria-label="Agent access" variant="outline" size="sm" spacing={0} disabled={busy} value={[access]} onValueChange={(next) => next[0] && next[0] !== access && void choose(next[0] as Access)}>
            {CHOICES.map((c) => (
              <ToggleGroupItem key={c.value} value={c.value}>
                {c.label}
              </ToggleGroupItem>
            ))}
          </ToggleGroup>
        </SettingsRow>
        <SettingsRow title="Status" description={problem ?? undefined} tone={problem ? "caution" : undefined}>
          <Badge variant={listening ? "success-light" : problem ? "warning-light" : "secondary"}>{listening ? "Listening" : problem ? "Not listening" : access === "off" ? "Off" : "Starts with the engine"}</Badge>
        </SettingsRow>
      </SettingsSection>
    </>
  )
}
