import { SectionError } from "./SectionError"
import styles from "./settings.module.css"
import { useResult } from "@/lib/use-result"
import { BackupRestore } from "./BackupRestore"

/** Backing up or restoring the records. */
export function BackupsPage() {
  const pending = useResult(() => window.copytrading.read.getRestoreCandidate(), "restore-candidate")
  return (
    <div className={styles.page}>
      {pending.status === "error" ? (
        <SectionError title="Restore status did not load" message={pending.error} onRetry={pending.retry} />
      ) : (
        // Stays mounted while the status reloads, so a note and a previewed backup are not lost.
        <BackupRestore pending={pending.status === "ready" ? pending.data : null} checking={pending.status === "loading"} onChanged={pending.retry} />
      )}
    </div>
  )
}
