import type { DiagnosticsEntry } from "../../../shared/contract"
import { Badge } from "@/components/arc/badge/badge"
import { dateTime } from "@/lib/format"
import { displayFields, isProblem, outcomeTitle, title } from "./journal"
import { SettingsRow } from "./SettingsRow"
import styles from "./settings.module.css"

/** One journal record: when it happened, how it ended, the fields worth reading, and the redacted payload it captured. */
export function JournalDetail({ entry }: { entry: DiagnosticsEntry }) {
  const fields = displayFields(entry)
  return (
    <section className={styles.detail} aria-label="Selected record">
      <div className={styles.detailHead}>
        <h3>{title(entry)}</h3>
        <Badge tone={isProblem(entry) ? "warning" : "success"}>{outcomeTitle(entry)}</Badge>
      </div>
      <div className={styles.rows}>
        <SettingsRow title="When">
          <span className={styles.value}>{dateTime(entry.at)}</span>
        </SettingsRow>
        {fields.map((field) => (
          <SettingsRow key={field.label} title={field.label}>
            <span className={`${styles.value} ${styles.breakAll}`}>{field.value}</span>
          </SettingsRow>
        ))}
      </div>
      {(entry.payload_json || entry.payload_unreadable) && (
        <div>
          <p className={styles.hint}>Payload, with keys removed</p>
          {entry.payload_unreadable ? <p className={styles.value}>This record’s bytes were not text, so they are not shown.</p> : <pre className={styles.payload}>{entry.payload_json}</pre>}
        </div>
      )}
    </section>
  )
}
