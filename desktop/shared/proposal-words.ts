import type { AgentProposal } from "./contract"

// What an agent or the assistant asked for, in plain words (AgentProposal+Display.swift, AgentCallerName.swift).
// Shared because the page lists these and main announces them with the same words.

/** "broker_state_mismatch" → "Broker state mismatch"; nothing → a dash. */
export function humanCode(raw: string | null | undefined): string {
  if (!raw) return "—"
  const spaced = raw.replaceAll("_", " ").replaceAll("-", " ")
  return spaced.charAt(0).toUpperCase() + spaced.slice(1)
}

export const ASSISTANT = "CopyTrading Assistant"
export const isAssistant = (path: string | null): boolean => path === ASSISTANT

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
  follow_stops: "Follow the guru's stops",
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
