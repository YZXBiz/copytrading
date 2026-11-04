import type { DiagnosticsEntry } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Frame, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { dateTime } from "@/lib/format"
import { displayFields, isProblem, outcomeTitle, title } from "./journal"
import { SettingsRow } from "./SettingsRow"

/** One journal record: when it happened, how it ended, the fields worth reading, and the redacted payload it captured. */
export function JournalDetail({ entry }: { entry: DiagnosticsEntry }) {
  const fields = displayFields(entry)
  return (
    <Frame spacing="sm" className="min-w-0">
      <FrameHeader className="flex-row items-center justify-between gap-3">
        <FrameTitle>{title(entry)}</FrameTitle>
        <Badge variant={isProblem(entry) ? "warning-light" : "success-light"}>{outcomeTitle(entry)}</Badge>
      </FrameHeader>
      <FramePanel className="p-0">
        <SettingsRow title="When">{dateTime(entry.at)}</SettingsRow>
        {fields.map((field) => (
          <SettingsRow key={field.label} title={field.label}>
            <span className="max-w-72 break-all text-right">{field.value}</span>
          </SettingsRow>
        ))}
      </FramePanel>
      {(entry.payload_json || entry.payload_unreadable) && (
        <FramePanel>
          <p className="text-muted-foreground mb-2 text-xs">Payload, with keys removed</p>
          {entry.payload_unreadable ? (
            <p className="text-sm">This record’s bytes were not text, so they are not shown.</p>
          ) : (
            <pre className="max-h-96 overflow-auto font-mono text-xs break-words whitespace-pre-wrap">{entry.payload_json}</pre>
          )}
        </FramePanel>
      )}
    </Frame>
  )
}
