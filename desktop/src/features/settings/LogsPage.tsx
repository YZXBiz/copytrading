import { useState } from "react"
import { JournalView } from "./JournalView"
import { LogHealth } from "./LogHealth"
import styles from "./settings.module.css"

/** Whether the engine's log is healthy, and the log itself. */
export function LogsPage() {
  const [journalBytes, setJournalBytes] = useState<number | null>(null)
  return (
    <div className={styles.page}>
      <LogHealth journalBytes={journalBytes} />
      <JournalView onBytes={setJournalBytes} />
    </div>
  )
}
