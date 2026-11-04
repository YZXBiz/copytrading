// Words for engine codes and sizes, as Humanize.swift and RestoreBlocker.swift put them. Never a raw snake_case code on screen.

import { humanCode } from "../../../shared/proposal-words"

export { humanCode }

/** "1 account", "2 accounts". */
export const count = (n: number, noun: string, plural = `${noun}s`): string => `${n.toLocaleString("en-US")} ${n === 1 ? noun : plural}`

/** "a", "a, b", "a, b, c": the way the app lists things. */
export const joined = (parts: string[]): string => parts.join(", ")

/** 1.5 MB, 256 KB, 0 bytes. Decimal units, as macOS shows file sizes. */
export function bytes(n: number): string {
  if (n < 1000) return count(n, "byte")
  const units = ["KB", "MB", "GB", "TB"]
  let value = n
  let unit = -1
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000
    unit++
  }
  return `${value >= 100 ? Math.round(value) : Number(value.toFixed(1))} ${units[unit]}`
}

const BLOCKERS: Record<string, string> = {
  broker_state_mismatch: "Alpaca's orders or holdings changed since the backup",
  broker_evidence_unavailable: "Alpaca could not be reached to check the backup",
  account_identity_mismatch: "the backup's account doesn't match the keys on this Mac",
  account_outbox_pending: "a notification in the backup was never sent",
  application_work_pending: "posts in the backup were still being read",
  account_snapshot_incomplete: "an account in the backup is incomplete",
  candidate_changed: "the backup's files changed or failed their check",
  candidate_invalid: "the backup's files changed or failed their check",
}

/** Why a restore was refused, in words that say what to do about it. */
export const restoreBlocker = (code: string): string => BLOCKERS[code] ?? humanCode(code)
