import type { ActApi } from "../../../shared/contract"
import { joined, restoreBlocker } from "./words"

type Acts = Pick<ActApi, "prepareRestoreCandidate" | "restorePreflight" | "completeRestoreCandidate">

export type RestoreOutcome =
  | { status: "done" }
  | { status: "blocked"; blockers: string[] }
  | { status: "cancelled" }
  | { status: "failed"; error: string }

/**
 * Checks a prepared restore against the owner's broker and, if it matches, completes it. Completing is the
 * confirmed step: main asks the owner first, and a Cancel there stops everything with nothing replaced.
 */
export async function finishRestore(acts: Pick<Acts, "restorePreflight" | "completeRestoreCandidate">, candidateId: string): Promise<RestoreOutcome> {
  const preflight = await acts.restorePreflight({ candidate_id: candidateId })
  if (!preflight.ok) return { status: "failed", error: preflight.error }
  const { eligible, blockers, completion_token } = preflight.value
  if (!eligible || !completion_token) return { status: "blocked", blockers }
  const done = await acts.completeRestoreCandidate({ candidate_id: candidateId, completion_token })
  if (done.ok) return { status: "done" }
  return done.cancelled ? { status: "cancelled" } : { status: "failed", error: done.error }
}

/** Prepares a previewed backup, then finishes it. */
export async function restoreFromPreview(acts: Acts, stagingId: string): Promise<RestoreOutcome> {
  const prepared = await acts.prepareRestoreCandidate({ staging_id: stagingId })
  return prepared.ok ? finishRestore(acts, prepared.value.candidate_id) : { status: "failed", error: prepared.error }
}

/** "Before it can restore: …", each refusal in words. */
export const blockersText = (blockers: string[]): string => `Before it can restore: ${joined(blockers.map(restoreBlocker))}`
