import { useState } from "react"
import type { AgentAccess as Access, AgentAccessState } from "../../../shared/contract"
import { Badge } from "@/components/arc/badge/badge"
import SegmentedControl from "@/components/arc/segmented-control/segmented-control"
import { useResult } from "@/lib/use-result"
import { Note, type NoteState } from "./Note"
import { SectionError } from "./SectionError"
import { SettingsRow } from "./SettingsRow"
import { SectionSkeleton, SettingsSection } from "./SettingsSection"

// How far agents such as Claude Code may go through the copytrading command and MCP server.
const CHOICES: { value: Access; label: string; detail: string }[] = [
  { value: "off", label: "Nothing", detail: "Agents cannot reach CopyTrading." },
  { value: "read_pause", label: "Read and pause", detail: "Agents can read your accounts and pause copying. Pausing always works." },
  { value: "propose", label: "Ask for approval", detail: "Agents can read, pause, and ask. Anything that could trade waits for your approval here." },
]

/** Whether agents may connect and how far; changing it asks the owner first (main shows the dialog). */
export function AgentAccess() {
  const state = useResult(() => window.copytrading.read.getAgentAccess(), "agent-access")
  const [note, setNote] = useState<NoteState | null>(null)
  const [busy, setBusy] = useState(false)
  // What main said after the owner's last change; the read above is only the first answer.
  const [changed, setChanged] = useState<AgentAccessState | null>(null)

  if (state.status === "loading") return <SectionSkeleton rows={2} label="Loading agent access" />
  if (state.status === "error") return <SectionError title="Agent access did not load" message={state.error} onRetry={state.retry} />
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
      <SettingsSection title="Allow agents to" hint="Agents connect while the app runs.">
        <SettingsRow title="Access" description={chosen.detail} stacked>
          <SegmentedControl label="Agent access" options={CHOICES.map(({ value, label }) => ({ value, label }))} value={access} onValueChange={(next) => !busy && next !== access && void choose(next as Access)} />
        </SettingsRow>
        <SettingsRow title="Status" description={problem ?? undefined} tone={problem ? "caution" : undefined}>
          <Badge tone={listening ? "success" : problem ? "warning" : "neutral"}>{listening ? "Listening" : problem ? "Not listening" : access === "off" ? "Off" : "Starts with the engine"}</Badge>
        </SettingsRow>
      </SettingsSection>
    </>
  )
}
