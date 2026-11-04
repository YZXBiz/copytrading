import { useState } from "react"
import type { BackupManifest, PendingRestoreCandidate, RestorePreview } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Button } from "@/components/ui/button"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { dateTime } from "@/lib/format"
import { Note, type NoteState } from "./Note"
import { SettingsRow } from "./SettingsRow"
import { SettingsSection } from "./SettingsSection"
import { type RestoreOutcome, blockersText, finishRestore, restoreFromPreview } from "./restore-flow"
import { count, joined } from "./words"

const acts = () => window.copytrading.act

function outcomeNote(outcome: RestoreOutcome): NoteState | null {
  switch (outcome.status) {
    case "done":
      return { kind: "done", text: "Restored. Quit and reopen CopyTrading to use the restored records." }
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
    <SettingsSection title="Restore Preview">
      <SettingsRow title="Same installation">
        <Badge variant={preview.matches_installation ? "success-light" : "destructive-light"}>{preview.matches_installation ? "Yes" : "No"}</Badge>
      </SettingsRow>
      <SettingsRow title="Accounts">{preview.account_ids.length ? joined(preview.account_ids) : "None"}</SettingsRow>
      <SettingsRow title="Environments">{preview.environment_ids.length ? joined(preview.environment_ids) : "None"}</SettingsRow>
      <SettingsRow title="Backup identity">
        <Tooltip>
          <TooltipTrigger type="button" className="cursor-help font-mono text-xs">
            {preview.installation_id.slice(0, 12)}
          </TooltipTrigger>
          <TooltipContent>{`Installation ${preview.installation_id}\nStaging ${preview.staging_id}`}</TooltipContent>
        </Tooltip>
      </SettingsRow>
      <SettingsRow title="Nothing has changed yet" description="Restoring first checks the backup against your broker's account, orders, and holdings, and stops if they don't match.">
        <Button type="button" size="sm" disabled={busy || !preview.matches_installation} onClick={onRestore}>
          Restore This Backup
        </Button>
      </SettingsRow>
    </SettingsSection>
  )
}

function PendingRows({ pending, busy, onResume, onRollBack }: { pending: PendingRestoreCandidate; busy: boolean; onResume: () => void; onRollBack: () => void }) {
  return (
    <SettingsSection title="Restore in Progress">
      <SettingsRow
        title="Restore candidate"
        description={
          pending.candidate_valid
            ? "Resume with a read-only broker check, or roll back to the previous generation."
            : "Roll back to the previous generation."
        }
      >
        <Tooltip>
          <TooltipTrigger type="button" className="cursor-help">
            <Badge variant={pending.candidate_valid ? "warning-light" : "destructive-light"}>{pending.candidate_valid ? "Passed validation" : "Failed validation"}</Badge>
          </TooltipTrigger>
          <TooltipContent>{`Candidate ${pending.candidate_id}\nPrevious generation ${pending.previous_generation}\nActive generation ${pending.active_generation}`}</TooltipContent>
        </Tooltip>
      </SettingsRow>
      <SettingsRow title="Resume Restore">
        <Button type="button" size="sm" disabled={busy || !pending.candidate_valid} onClick={onResume}>
          Resume
        </Button>
      </SettingsRow>
      <SettingsRow title="Roll Back Restore">
        <Button type="button" size="sm" variant="destructive" disabled={busy} onClick={onRollBack}>
          Roll Back
        </Button>
      </SettingsRow>
    </SettingsSection>
  )
}

/** Backing up the records, and restoring from a backup: preview first, then prepare, check against the broker, and complete (the last step is confirmed by main). */
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

  const restore = (text: string, run: () => Promise<RestoreOutcome>) =>
    work(text, async () => {
      const outcome = await run()
      if (outcome.status === "done") setPreview(null)
      return outcomeNote(outcome)
    })

  const rollBack = (candidate: PendingRestoreCandidate) =>
    work("Rolling back…", async () => {
      const result = await acts().abortRestoreCandidate({ candidate_id: candidate.candidate_id })
      return result.ok ? { kind: "done", text: "Rolled back. Your records are as they were." } : { kind: "problem", text: result.error }
    })

  return (
    <>
      <SettingsSection title="Backup & Restore" hint="Holds your records, setup, posts, and attachments. Keys and logs are left out.">
        <SettingsRow title="Create Backup…" description="Copying waits a moment while it runs.">
          <Button type="button" size="sm" variant="outline" disabled={busy} onClick={createBackup}>
            Create
          </Button>
        </SettingsRow>
        <SettingsRow title="Restore from Backup…" description="Shows what a backup holds first. Nothing changes until you restore it.">
          <Button type="button" size="sm" variant="outline" disabled={busy || checking || pending !== null} onClick={openBackup}>
            Choose
          </Button>
        </SettingsRow>
        {manifest && <SettingsRow title="Last verified backup">{`${dateTime(manifest.created_at)} · ${count(manifest.members.length, "file")}`}</SettingsRow>}
      </SettingsSection>
      {note && <Note note={note} />}
      {preview && pending === null && (
        <PreviewRows preview={preview} busy={busy} onRestore={() => restore("Preparing the restore and checking it again…", () => restoreFromPreview(acts(), preview.staging_id))} />
      )}
      {pending && (
        <PendingRows
          pending={pending}
          busy={busy}
          onResume={() => restore("Checking the restore again…", () => finishRestore(acts(), pending.candidate_id))}
          onRollBack={() => rollBack(pending)}
        />
      )}
    </>
  )
}
