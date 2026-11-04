import { useState } from "react"
import { JournalView } from "./JournalView"
import { LogHealth } from "./LogHealth"

/** Whether the engine's log is healthy, and the log itself. */
export function LogsPage() {
  const [journalBytes, setJournalBytes] = useState<number | null>(null)
  return (
    <div className="flex flex-col gap-5">
      <LogHealth journalBytes={journalBytes} />
      <JournalView onBytes={setJournalBytes} />
    </div>
  )
}
