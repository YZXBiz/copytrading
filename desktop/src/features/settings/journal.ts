import type { DiagnosticsEntry } from "../../../shared/contract"
import { money, shares } from "@/lib/format"
import { bytes, humanCode } from "./words"

// How a journal record reads: DiagnosticsJournalEntry+Display.swift and DiagnosticsFilter.swift.

export const FILTERS = ["all", "captures", "trading", "problems"] as const
export type Filter = (typeof FILTERS)[number]

export const FILTER_TITLE: Record<Filter, string> = { all: "All", captures: "Captures", trading: "Trading", problems: "Problems" }
export const FILTER_EMPTY: Record<Filter, string> = {
  all: "Nothing logged yet",
  captures: "No captured posts or model calls",
  trading: "No trading steps yet",
  problems: "No problems recorded",
}

const STAGES: Record<string, string> = {
  captured: "Self-test captured",
  parsed: "Self-test read",
  completed: "Self-test finished",
  failed: "Self-test failed",
}

const LEDGER: Record<string, string> = {
  account_bound: "Account connected",
  signal_rejected: "Post refused",
  message: "Post received",
  skipped: "Order skipped",
  message_done: "Post finished",
  order_prepared: "Order prepared",
  submit_started: "Order sending",
  submission_aborted: "Order not sent",
  submission_uncertain: "Order unconfirmed",
  broker_acknowledged: "Broker accepted",
  cancel_requested: "Cancel asked",
  quote_unavailable: "No quote",
  submit_error: "Order refused",
  submission_quote: "Quote at sending",
  manual_sale_recorded: "Sale recorded",
  order_intent_released: "Order released",
  late_order_incident_cleared: "Late order cleared",
  order_update: "Order update",
  late_order_incident_opened: "Late order found",
  late_order_incident_reopened: "Late order found again",
}

const PAYLOADS: Record<string, string> = { source_event: "Source post", model_request: "Model request", model_response: "Model reply" }

const TRADING: Record<string, string> = {
  "source.forward": "Post forwarded",
  workflow: "Workflow step",
  "model.parse": "Interpretation",
  "destination.receive": "Account delivery",
  "execution.risk_checks": "Risk checks",
  "execution.order_submission": "Order submission",
  "execution.quote_snapshot": "Quote snapshot",
}

/** What happened, in words. */
export function title(entry: DiagnosticsEntry): string {
  switch (entry.kind) {
    case "stage":
      return STAGES[entry.name] ?? "Self-test step"
    case "payload":
      return PAYLOADS[entry.name] ?? "Captured payload"
    case "trading":
      return entry.name === "execution.ledger_event" ? (LEDGER[entry.outcome] ?? "Ledger entry") : (TRADING[entry.name] ?? "Trading step")
  }
}

const OUTCOMES: Record<string, string> = {
  returned: "Completed",
  raised: "Failed",
  observed: "Recorded",
  complete: "Captured",
  oversize: "Too large",
  missing: "Missing",
  incomplete: "Not captured",
  accepted: "Accepted",
  parsed: "Read",
  completed: "Completed",
  failed: "Failed",
  error: "Failed",
}

/** How it ended, in words; a ledger event carries its name in the title instead. */
export function outcomeTitle(entry: DiagnosticsEntry): string {
  return OUTCOMES[entry.outcome] ?? (entry.kind === "trading" && entry.name === "execution.ledger_event" ? "Recorded" : humanCode(entry.outcome))
}

const PROBLEMS = new Set([
  "raised", "failed", "error", "oversize", "missing", "incomplete", "submit_error", "submission_aborted", "submission_uncertain",
  "quote_unavailable", "signal_rejected", "late_order_incident_opened", "late_order_incident_reopened",
])

export const isProblem = (entry: DiagnosticsEntry): boolean => PROBLEMS.has(entry.outcome)

export function includes(filter: Filter, entry: DiagnosticsEntry): boolean {
  switch (filter) {
    case "all":
      return true
    case "captures":
      return entry.kind === "payload"
    case "trading":
      return entry.kind === "trading"
    case "problems":
      return isProblem(entry)
  }
}

/** Lowercased text the search box matches. */
export const searchText = (entry: DiagnosticsEntry): string =>
  [entry.name, entry.outcome, entry.trace_id ?? "", entry.workflow_id ?? "", entry.payload_json ?? "", ...entry.fields.map((f) => f.value)].join(" ").toLowerCase()

const isNumber = (value: string) => value.trim() !== "" && Number.isFinite(Number(value))

/** The fields worth reading: what the title and badge already say, and internal flags, are left out. */
export function displayFields(entry: DiagnosticsEntry): { label: string; value: string }[] {
  const byName = new Map(entry.fields.map((f) => [f.name, f.value]))
  const side = byName.get("side")
  const out: { label: string; value: string }[] = []
  const add = (name: string, label: string, show: (value: string) => string = (v) => v) => {
    const value = byName.get(name)
    if (value !== undefined) out.push({ label, value: show(value) })
  }
  const number = (format: (value: string) => string) => (value: string) => (isNumber(value) ? format(value) : value)
  add("symbol", "Stock", (v) => [side && (side === "sell" ? "Sell" : "Buy"), v].filter(Boolean).join(" "))
  add("qty", "Shares", number(shares))
  add("limit_price", "Limit price", number(money))
  add("source_price", "Guru's price", number(money))
  add("status", "Status", humanCode)
  add("filled_qty", "Filled", number(shares))
  add("filled_avg_price", "Average fill", number(money))
  add("reason", "Reason", humanCode)
  add("previous_stage", "After", (v) => STAGES[v] ?? humanCode(v))
  // A post from Discord has no model provider; the engine journals "other".
  const provider = byName.get("provider")
  if (provider && provider !== "other") out.push({ label: "Provider", value: provider })
  add("command_id", "Command")
  add("workflow_id", "Workflow")
  add("trace_id", "Trace")
  add("destination_id", "Destination")
  add("attempt", "Attempt")
  add("signal_ref", "Signal")
  add("payload_bytes", "Payload size", number((v) => bytes(Number(v))))
  add("redacted_fields", "Values redacted")
  return out
}
