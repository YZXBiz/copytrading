import type { AgentAuditEntry, AgentProposal, TradingConfiguration } from "../../../shared/contract"
import { ago } from "@/lib/format"
import { humanCode } from "./words"

// What an agent or the assistant asked for, in plain words: AgentProposal+Display.swift, AgentAuditRow.swift, AgentCallerName.swift.

export const ASSISTANT = "CopyTrading Assistant"
export const isAssistant = (path: string | null): boolean => path === ASSISTANT

/** The program behind a request, by name rather than path. */
export function callerName(path: string | null): string {
  if (!path) return "An unknown program"
  return isAssistant(path) ? ASSISTANT : (path.split("/").pop() ?? path)
}

const LIMIT_TITLES: Record<string, string> = {
  max_order_usd: "Largest single buy",
  max_symbol_usd: "Maximum per stock",
  max_total_usd: "Maximum total exposure",
  daily_loss_cap_usd: "Daily loss cap",
  max_above_signal_pct: "Maximum above signal price (%)",
  max_below_signal_pct: "Lowest sell price (% under the guru's)",
  max_entries_per_day: "Entries per day",
  max_signal_age_seconds: "Maximum signal age (seconds)",
  order_timeout_seconds: "Order timeout (seconds)",
  poll_seconds: "Check for posts every (seconds)",
  extended_hours: "Trade in extended hours",
  overnight: "Trade overnight",
  copy_exits: "Copy exits",
  approve_orders: "Ask me before sending orders",
}
const DOLLAR_LIMITS = new Set(["max_order_usd", "max_symbol_usd", "max_total_usd", "daily_loss_cap_usd"])

export const limitTitle = (field: string): string => LIMIT_TITLES[field] ?? humanCode(field)

/** "$1,500", "$12.50"; whole dollars drop their cents. */
function dollars(value: string): string {
  const n = Number(value)
  if (value.trim() === "" || !Number.isFinite(n)) return "—"
  return n.toLocaleString("en-US", { style: "currency", currency: "USD", minimumFractionDigits: Number.isInteger(n) ? 0 : 2, maximumFractionDigits: 2 })
}

export function limitValue(field: string, value: string): string {
  if (value === "true") return "On"
  if (value === "false") return "Off"
  return DOLLAR_LIMITS.has(field) ? dollars(value) : value
}

/** What approving would do, in plain words. */
export function summary(proposal: AgentProposal): string {
  const s = proposal.subject
  switch (s.kind) {
    case "resume_account":
      return `Start copying into ${s.account_id}`
    case "set_recovery":
      return `In ${s.account_id}, after a restart: ${s.preference === "automatic" ? "Resume copying" : s.preference === "manual" ? "Wait for me" : humanCode(s.preference)}`
    case "start_processing":
      return "Start copying"
    case "apply_setup":
      return "Apply the setup, with live accounts"
    case "set_account_limits":
      return `In ${s.account_id}: ${s.changes.map((c) => `${limitTitle(c.field)} ${limitValue(c.field, c.value)}`).join(", ")}`
    case "confirm_manual_order": {
      const type = s.limit_price ? `limit ${dollars(s.limit_price)}` : humanCode(s.order_type).toLowerCase()
      return `${humanCode(s.side)} ${s.quantity} ${s.symbol}, ${type}, in ${s.account_id}`
    }
  }
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

/** "Largest single buy · You · 5 min ago". */
export function auditLine(entry: AgentAuditEntry, now: Date): string {
  const caller = entry.actor === "owner" ? "You" : callerName(entry.caller_path)
  return `${caller} · ${ago(entry.at, now)}`
}
