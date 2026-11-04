import type { ActApi } from "../../../shared/contract"
import { joined, restoreBlocker } from "./words"

export type RestoreOutcome =
  | { status: "done" }
  | { status: "blocked"; blockers: string[] }
  | { status: "cancelled" }
  | { status: "failed"; error: string }

/**
 * Restores a previewed backup (`staging_id`) or finishes a half-done one (`candidate_id`). Main asks the owner first, then
 * stops the engine, switches to the restored data, checks it against the broker and restarts; a Cancel there changes nothing,
 * and any failure puts the old data back.
 */
export async function restore(acts: Pick<ActApi, "activateRestore">, target: { staging_id: string } | { candidate_id: string }): Promise<RestoreOutcome> {
  const done = await acts.activateRestore(target)
  if (!done.ok) return done.cancelled ? { status: "cancelled" } : { status: "failed", error: done.error }
  return done.value.status === "restored" ? { status: "done" } : { status: "blocked", blockers: done.value.blockers }
}

/** "Before it can restore: …", each refusal in words. */
export const blockersText = (blockers: string[]): string => `Before it can restore: ${joined(blockers.map(restoreBlocker))}`
