import type { AgentAuditEntry, AgentProposal, TradingConfiguration } from "../../../shared/contract"
import { ASSISTANT, humanCode, isAssistant, limitTitle, limitValue, summary } from "../../../shared/proposal-words"
import { ago } from "@/lib/format"

// What an agent or the assistant asked for, in plain words: AgentProposal+Display.swift, AgentAuditRow.swift, AgentCallerName.swift.
// The summary and the limit words are in shared/ because main announces requests with them.
export { ASSISTANT, isAssistant, limitTitle, limitValue, summary }

/** The program behind a request, by name rather than path. */
export function callerName(path: string | null): string {
  if (!path) return "An unknown program"
  return isAssistant(path) ? ASSISTANT : (path.split("/").pop() ?? path)
}

/** The account the request is about; null when it starts copying the whole setup. */
export function accountOf(proposal: AgentProposal): string | null {
  const s = proposal.subject
  return s.kind === "start_processing" || s.kind === "apply_setup" ? null : s.account_id
}

/** Whether approving could touch real money: a live account, or a setup with live accounts. */
export function isLive(proposal: AgentProposal, setup: TradingConfiguration | null): boolean {
  const s = proposal.subject
  if (s.kind === "confirm_manual_order") return s.environment === "live"
  if (s.kind === "apply_setup") return true
  const id = accountOf(proposal)
  return setup?.accounts.find((a) => a.id === id)?.environment === "live"
}

/** The engine finishes these itself on approval; the rest it leaves running until the app applies them. */
export const canApprove = (proposal: AgentProposal): boolean => proposal.subject.kind === "resume_account" || proposal.subject.kind === "confirm_manual_order"

/** What a limits request would change: each setting, its value now, and the value after. */
export function limitRows(proposal: AgentProposal, setup: TradingConfiguration | null): { title: string; now: string; after: string }[] {
  const s = proposal.subject
  if (s.kind !== "set_account_limits") return []
  const policy = setup?.accounts.find((a) => a.id === s.account_id)?.policy as unknown as Record<string, unknown> | undefined
  return s.changes.map((c) => ({
    title: limitTitle(c.field),
    now: policy && c.field in policy ? limitValue(c.field, String(policy[c.field])) : "—",
    after: limitValue(c.field, c.value),
  }))
}

/** Where a request stands, for the assistant's card and the list: waiting, or how it ended. */
export function statusLine(proposal: AgentProposal): string {
  switch (proposal.state) {
    case "pending":
      return "Waiting for your approval"
    case "running":
      return "Approved, working on it"
    case "succeeded":
      return "Approved and done"
    case "rejected":
      return "You turned this down"
    case "expired":
      return "Expired before approval"
    case "failed":
    case "outcome_unknown":
    case "discarded":
      return humanCode(proposal.state)
  }
}

export function resultMessage(proposal: AgentProposal): string {
  const what = summary(proposal)
  switch (proposal.state) {
    case "succeeded":
      return `Done: ${what}.`
    case "failed":
      return `Could not complete: ${what} (${humanCode(proposal.outcome?.code ?? "failed")}).`
    case "outcome_unknown":
      return `Sent, but the result is not confirmed yet: ${what}. Check Accounts.`
    case "expired":
      return "The request expired before approval."
    default:
      return `${humanCode(proposal.state)}: ${what}.`
  }
}

export type Tone = "success" | "warning" | "destructive" | "secondary" | "outline"

/** How a recorded request ended, in words and in colour. */
export function auditOutcome(entry: AgentAuditEntry): { text: string; tone: Tone } {
  const text = entry.outcome === "ok" ? "Done" : entry.outcome === "proposed" ? "Waiting for you" : humanCode(entry.outcome)
  switch (entry.outcome) {
    case "ok":
    case "approved":
    case "succeeded":
      return { text, tone: "success" }
    case "proposed":
      return { text, tone: "secondary" }
    case "locked":
    case "forbidden":
    case "busy":
    case "cooling_down":
    case "proposal_limit":
    case "rejected":
    case "expired":
      return { text, tone: "warning" }
    case "failed":
    case "outcome_unknown":
    case "unavailable":
    case "invalid_request":
    case "conflict":
      return { text, tone: "destructive" }
    default:
      return { text, tone: "outline" }
  }
}

/** Who made a recorded request or decision: "You", or the agent's name. */
export const auditWho = (entry: AgentAuditEntry): string => (entry.actor === "owner" ? "You" : callerName(entry.caller_path))

/** How long ago it was recorded: "5 min ago". */
export const auditWhen = (entry: AgentAuditEntry, now: Date): string => ago(entry.at, now)
