import type { TradingStatus } from "../../../shared/contract"
import { joinAnd } from "../../../shared/start-failure"
import { STEPS, type Progress } from "./state"
import type { Start } from "./setup-store"

export interface StartStatus {
  text: string
  detail: string | null
  tone: "working" | "positive" | "caution" | "neutral"
}

/** What the start bar says about the setup right now, in the order a person would care (SetupChangesStatus.swift). */
export function startStatus(input: {
  start: Start
  progress: Progress
  trading: TradingStatus | null
  isCopying: boolean
  hasSaved: boolean
  hasUnsaved: boolean
}): StartStatus {
  const { start, progress, trading, isCopying, hasSaved, hasUnsaved } = input
  switch (start.phase) {
    case "checking":
      return { text: "Checking every connection…", detail: null, tone: "working" }
    case "starting":
      return { text: "Saving and starting…", detail: null, tone: "working" }
    case "applying":
      return { text: "Applying your changes…", detail: "Copying is paused for a few seconds. A post sent meanwhile is still copied.", tone: "working" }
    case "pending":
      return { text: "Starting your new setup…", detail: "CopyTrading is waiting for the engine to confirm it.", tone: "working" }
    case "failed": {
      const problems = start.report?.checks.filter((c) => c.state === "failed").length ?? 0
      if (!problems) return { text: "Not started", detail: start.message, tone: "caution" }
      return {
        text: problems === 1 ? "One check needs attention" : `${problems} checks need attention`,
        detail: `${problems === 1 ? "Review it" : "Review them"}, then start again. Nothing was saved.`,
        tone: "caution",
      }
    }
    case "started":
      if (start.paused.length) {
        return {
          text: "Started, but not buying everywhere",
          detail: `${joinAnd(start.paused)} ${start.paused.length === 1 ? "is" : "are"} not buying yet. Resume ${start.paused.length === 1 ? "it" : "them"} on the account page.`,
          tone: "caution",
        }
      }
      break
    default:
  }
  if (!trading) return { text: "Waiting for the engine…", detail: "Start copying is ready once it answers.", tone: "working" }
  if (isCopying) {
    return hasUnsaved
      ? {
          text: "You changed the setup",
          detail: "Apply changes to use it. Copying restarts in a few seconds, and any post sent meanwhile is still copied.",
          tone: "neutral",
        }
      : { text: "Copying is running", detail: null, tone: "positive" }
  }
  if (!progress.isReadyToCheck) {
    const next = STEPS.find((s) => s.id === progress.next)
    return { text: `${progress.done.size} of ${STEPS.length} steps done`, detail: next ? `Next: ${next.title}.` : null, tone: "neutral" }
  }
  if (hasSaved && hasUnsaved) return { text: "You have unsaved changes", detail: "Starting checks and saves them.", tone: "neutral" }
  return { text: "Ready to start", detail: "Every connection is checked first. Nothing is saved or traded before that.", tone: "neutral" }
}

/** Apply changes can run: copying runs on the saved setup, the form differs from it and is filled in, and nothing is under way. */
export const canApplyChanges = (input: { start: Start; progress: Progress; isCopying: boolean; hasUnsaved: boolean }): boolean =>
  input.isCopying &&
  input.hasUnsaved &&
  input.progress.isReadyToCheck &&
  !["checking", "starting", "applying", "pending"].includes(input.start.phase)

/** Start copying can run: the four steps are filled in, copying is stopped, and no check or start is under way. */
export const canStartCopying = (input: { start: Start; progress: Progress; trading: TradingStatus | null }): boolean =>
  input.progress.isReadyToCheck &&
  (input.trading?.state === "paused" || input.trading?.state === "failed") &&
  input.start.phase !== "checking" &&
  input.start.phase !== "starting" &&
  input.start.phase !== "applying" &&
  input.start.phase !== "pending"
