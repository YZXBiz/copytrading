import { useState } from "react"
import type { BackupManifest, PendingRestoreCandidate, RestorePreview } from "../../../shared/contract"
import { Badge } from "@/components/arc/badge/badge"
import { Button } from "@/components/arc/button/button"
import { Tooltip } from "@/components/arc/tooltip/tooltip"
import { dateTime } from "@/lib/format"
import { Note, type NoteState } from "./Note"
import { SettingsRow } from "./SettingsRow"
import { SettingsSection } from "./SettingsSection"
import { type RestoreOutcome, blockersText, restore } from "./restore-flow"
import { count, joined } from "./words"
import styles from "./settings.module.css"

const acts = () => window.copytrading.act

function outcomeNote(outcome: RestoreOutcome): NoteState | null {
  switch (outcome.status) {
    case "done":
      return { kind: "done", text: "Restored. Each account's buys stay off until you turn them back on." }
    case "blocked":
      return { kind: "problem", text: blockersText(outcome.blockers) }
    case "failed":
      return { kind: "problem", text: outcome.error }
    case "cancelled":
      return null
  }
}

function PreviewRows({ preview, busy, onRestore }: { preview: RestorePreview; busy: boolean; onRestore: () => void }) {
  return (
    <SettingsSection title="Restore preview">
      <SettingsRow title="Same installation">
        <Badge tone={preview.matches_installation ? "success" : "danger"}>{preview.matches_installation ? "Yes" : "No"}</Badge>
      </SettingsRow>
      <SettingsRow title="Accounts">{preview.account_ids.length ? joined(preview.account_ids) : "None"}</SettingsRow>
      <SettingsRow title="Environments">{preview.environment_ids.length ? joined(preview.environment_ids) : "None"}</SettingsRow>
      <SettingsRow title="Backup identity">
        <Tooltip content={`Installation ${preview.installation_id}\nStaging ${preview.staging_id}`}>
          <button type="button" className={`${styles.mono} ${styles.value}`} style={{ border: 0, background: "none", padding: 0, cursor: "help" }}>
            {preview.installation_id.slice(0, 12)}
          </button>
        </Tooltip>
      </SettingsRow>
      <SettingsRow title="Nothing has changed yet" description="Restoring first checks the backup against your broker's account, orders, and holdings, and stops if they don't match.">
        <Button type="button" size="sm" disabled={busy || !preview.matches_installation} onClick={onRestore}>
          Restore this backup
        </Button>
      </SettingsRow>
    </SettingsSection>
  )
}

function PendingRows({ pending, busy, onResume, onRollBack }: { pending: PendingRestoreCandidate; busy: boolean; onResume: () => void; onRollBack: () => void }) {
  return (
    <SettingsSection title="Restore in progress">
      <SettingsRow
        title="Restore candidate"
        description={
          pending.candidate_valid
            ? "Resume with a read-only broker check, or roll back to the previous generation."
            : "Roll back to the previous generation."
        }
      >
        <Tooltip content={`Candidate ${pending.candidate_id}\nPrevious generation ${pending.previous_generation}\nActive generation ${pending.active_generation}`}>
          <button type="button" style={{ border: 0, background: "none", padding: 0, cursor: "help" }}>
            <Badge tone={pending.candidate_valid ? "warning" : "danger"}>{pending.candidate_valid ? "Passed validation" : "Failed validation"}</Badge>
          </button>
        </Tooltip>
      </SettingsRow>
      <SettingsRow title="Resume restore">
        <Button type="button" size="sm" disabled={busy || !pending.candidate_valid} onClick={onResume}>
          Resume
        </Button>
      </SettingsRow>
      <SettingsRow title="Roll back restore">
        <Button type="button" size="sm" variant="danger" disabled={busy} onClick={onRollBack}>
          Roll back
        </Button>
      </SettingsRow>
    </SettingsSection>
  )
}

/** Backing up the records, and restoring from a backup: preview first, then restore (main confirms, switches the data, checks the broker, restarts the engine). */
export function BackupRestore({ pending, checking, onChanged }: { pending: PendingRestoreCandidate | null; checking: boolean; onChanged: () => void }) {
  const [busy, setBusy] = useState(false)
  const [note, setNote] = useState<NoteState | null>(null)
  const [manifest, setManifest] = useState<BackupManifest | null>(null)
  const [preview, setPreview] = useState<RestorePreview | null>(null)

  async function work(text: string, run: () => Promise<NoteState | null>) {
    setBusy(true)
    setNote({ kind: "working", text })
    setNote(await run())
    setBusy(false)
    onChanged()
  }

  const createBackup = async () => {
    const chosen = await acts().chooseBackupDestination()
    if (!chosen.ok) return setNote({ kind: "problem", text: chosen.error })
    if (!chosen.value) return
    const destination = chosen.value
    await work("Backing up your records…", async () => {
      const result = await acts().createBackup({ destination })
      if (!result.ok) return { kind: "problem", text: result.error }
      setManifest(result.value)
      return { kind: "done", text: `Backup saved: ${count(result.value.members.length, "file")}.` }
    })
  }

  const openBackup = async () => {
    const chosen = await acts().chooseRestoreArchive()
    if (!chosen.ok) return setNote({ kind: "problem", text: chosen.error })
    if (!chosen.value) return
    const archive_path = chosen.value
    await work("Reading the backup…", async () => {
      const result = await acts().previewRestore({ archive_path })
      if (!result.ok) return { kind: "problem", text: result.error }
      setPreview(result.value)
      return null
    })
  }

  const restoreFrom = (text: string, target: { staging_id: string } | { candidate_id: string }) =>
    work(text, async () => {
      const outcome = await restore(acts(), target)
      if (outcome.status === "done") setPreview(null)
      return outcomeNote(outcome)
    })

  const rollBack = (candidate: PendingRestoreCandidate) =>
    work("Undoing the restore…", async () => {
      const result = await acts().rollbackRestore({ candidate_id: candidate.candidate_id })
      if (result.ok) return { kind: "done", text: "Restore undone. CopyTrading is back on your data from before." }
      return result.cancelled ? null : { kind: "problem", text: result.error }
    })

  return (
    <>
      <SettingsSection title="Backup and restore" hint="Records, setup, posts, attachments. No keys or logs.">
        <SettingsRow title="Create backup">
          <Button type="button" size="sm" variant="secondary" disabled={busy} onClick={createBackup}>
            Create
          </Button>
        </SettingsRow>
        <SettingsRow title="Restore from backup">
          <Button type="button" size="sm" variant="secondary" disabled={busy || checking || pending !== null} onClick={openBackup}>
            Choose
          </Button>
        </SettingsRow>
        {manifest && (
          <SettingsRow title="Last verified backup">
            <span className={styles.valueMuted}>{dateTime(manifest.created_at)}</span>
            <Badge outline>{count(manifest.members.length, "file")}</Badge>
          </SettingsRow>
        )}
      </SettingsSection>
      {note && <Note note={note} />}
      {preview && pending === null && (
        <PreviewRows preview={preview} busy={busy} onRestore={() => restoreFrom("Preparing the restore and checking it again…", { staging_id: preview.staging_id })} />
      )}
      {pending && (
        <PendingRows
          pending={pending}
          busy={busy}
          onResume={() => restoreFrom("Checking the restore again…", { candidate_id: pending.candidate_id })}
          onRollBack={() => rollBack(pending)}
        />
      )}
    </>
  )
}
