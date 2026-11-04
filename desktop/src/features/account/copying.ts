import type { AccountOverview, TradingStatus } from "../../../shared/contract"
import type { BadgeProps } from "@/components/reui/badge"
import { reasonText } from "@/lib/reasons"

// Whether CopyTrading copies into one account, in the five words the owner sees (CopyingState.swift), with the
// line under it saying why it stopped, what it waits for, or what is wrong while it still copies.

export type CopyingWord = "copying" | "sellsOnly" | "paused" | "stopped" | "notStarted"

export interface CopyingState {
  word: CopyingWord
  /** Why it stopped, what it waits for, or a warning while it copies; null when there is nothing to add. */
  detail: string | null
  /** Whether the line under "Copying" is something wrong, or only says when it copies. */
  warns: boolean
}

export const COPYING_TITLE: Record<CopyingWord, string> = {
  copying: "Copying",
  sellsOnly: "Sells only",
  paused: "Paused",
  stopped: "Stopped",
  notStarted: "Not started",
}

/** An account the engine could not open or keep: a problem, never the owner's choice. */
const UNHELD = new Set([
  "account_unavailable",
  "outside_open_orders",
  "broker_account_inactive",
  "account_in_use",
  "alpaca_account_shared",
  "record_unreadable",
  "broker_keys_rejected",
  "broker_unreachable",
])

const state = (word: CopyingWord, detail: string | null = null, warns = true): CopyingState => ({ word, detail, warns })

export function accountCopying(account: AccountOverview, status: TradingStatus | null): CopyingState {
  const readiness = account.readiness ?? ""
  if (account.active_configuration !== true) return state("notStarted")
  if (UNHELD.has(readiness)) return state("stopped", reasonText(readiness))
  if (status?.state === "failed") return state("stopped", reasonText(status.error_code ?? "processing_unavailable"))
  if (status?.state === "paused" || status?.state === "pausing" || readiness === "processing_stopped") return state("paused")
  if (account.entry_permission === "paused") return state("sellsOnly", "You paused new buys; sells still go through")
  if (readiness === "manual_resume_required") return state("sellsOnly", "Waiting for your Start Copying after a restart")
  if (account.entry_permission !== "enabled") return state("notStarted")
  switch (readiness) {
    case "enabled":
    case "unavailable":
      return state("copying")
    case "enabled_waiting_for_session":
      return state("copying", "Copies once the market opens", false)
    case "enabled_coins_only":
      return state("copying", "Coins now, stocks once the market opens", false)
    case "recovery_pending":
      return state("copying", "Checking the account after a restart")
    default:
      return state("copying", reasonText(readiness))
  }
}

/** Whether something is wrong, so the line under the word is shown. */
export const isWarning = ({ word, detail, warns }: CopyingState) => word === "sellsOnly" || word === "stopped" || (word === "copying" && detail !== null && warns)

export const badgeVariant = (s: CopyingState): BadgeProps["variant"] =>
  s.word === "stopped" ? "destructive-light" : isWarning(s) ? "warning-light" : s.word === "copying" ? "success-light" : "outline"

/** What the owner is told when an account stops on its own: which account, and what to do. */
export const stoppedTitle = (accountId: string) => `Copying into ${accountId} stopped`
export const STOPPED_BODY = "CopyTrading hit a problem it couldn't fix. Stop copying everywhere, then start again to reopen it."

/**
 * Why Resume cannot run, or null when it can. The engine takes a resume only while copying runs; starting
 * copying itself is the setup's Start, not an account's.
 */
export function resumeBlocked(account: AccountOverview, status: TradingStatus | null): string | null {
  if (account.active_configuration !== true) return "Save this account in Connections before copying into it."
  if (status?.state !== "running" && status?.state !== "degraded") return "Copying is off. Start it first, then resume this account."
  return null
}
