import { MENU_BAR_MODES, type MenuBarMode, THEMES, type Theme } from "../../../shared/contract"
import type {
  AgentAccess,
  AgentAccessState,
  AgentAuditEntry,
  AgentProposal,
  AssistantTurnPage,
  DiagnosticsEntry,
  EngineStatus,
  PendingRestoreCandidate,
  RestorePreview,
  Result,
  SecretStatus,
} from "../../../shared/contract"

// Settings and tools in the engine's wire shapes, for `COPYTRADING_FIXTURES=1` (the saved setup is people.ts's): the keys, a
// journal, two waiting requests, a few recorded ones, and a canned assistant answer. Times are on the fixture clock
// (2026-11-03T21:00:00Z). COPYTRADING_FIXTURE_STATE=pending-restore shows a half-finished restore.

type Params = Record<string, unknown> | undefined
const ok = async <T>(value: T): Promise<Result<T>> => ({ ok: true, value })

const secrets: SecretStatus = { discord_token: true, provider_api_key: true, notification_token: false, brokers: { "zhap-account-2": true, "zhap-account-3": true } }
const engine: EngineStatus = {
  instance_id: "fixture", state: "running", accepted: 14, pending: 0, completed: 14, telemetry_state: "healthy", telemetry_dropped: 0, telemetry_error_code: null,
  diagnostic_capture: { source_event_gaps: 0, model_request_gaps: 1, model_response_gaps: 0 },
}

const entry = (minute: number, over: Partial<DiagnosticsEntry>): DiagnosticsEntry => ({
  id: `${minute}-${over.name}-${over.outcome}`, kind: "trading", at: `2026-11-03T20:${String(minute).padStart(2, "0")}:12.482113+00:00`, name: "workflow", outcome: "returned",
  trace_id: null, workflow_id: null, fields: [], payload_json: null, payload_unreadable: false, ...over,
})

const journal: DiagnosticsEntry[] = [
  entry(52, { name: "execution.ledger_event", outcome: "order_update", fields: [{ name: "filled_qty", value: "2.052463" }, { name: "side", value: "sell" }, { name: "status", value: "filled" }, { name: "symbol", value: "SOXS" }] }),
  entry(51, { name: "execution.order_submission", outcome: "returned", fields: [{ name: "limit_price", value: "40.45" }, { name: "qty", value: "2.052463" }, { name: "side", value: "sell" }, { name: "symbol", value: "SOXS" }] }),
  entry(51, { name: "execution.risk_checks", outcome: "returned", fields: [{ name: "destination_id", value: "zhap-account-2" }] }),
  entry(50, { name: "model.parse", outcome: "returned", fields: [{ name: "provider", value: "deepseek" }, { name: "trace_id", value: "7c1e0a52b9" }] }),
  entry(50, { kind: "payload", name: "model_response", outcome: "complete", fields: [{ name: "payload_bytes", value: "412" }, { name: "redacted_fields", value: "0" }], payload_json: '{\n  "action": "close",\n  "price": "40.45",\n  "symbol": "SOXS"\n}' }),
  entry(49, { kind: "payload", name: "source_event", outcome: "complete", fields: [{ name: "payload_bytes", value: "96" }], payload_json: '{\n  "text": "SOXS sell 40.45"\n}' }),
  entry(47, { name: "execution.ledger_event", outcome: "submit_error", fields: [{ name: "reason", value: "price_too_high" }, { name: "symbol", value: "F" }] }),
  entry(44, { name: "source.forward", outcome: "returned" }),
  entry(40, { kind: "stage", name: "completed", outcome: "completed", fields: [{ name: "previous_stage", value: "parsed" }] }),
  entry(31, { kind: "payload", name: "model_request", outcome: "oversize", fields: [{ name: "payload_bytes", value: "2400000" }] }),
]

const resume = { kind: "resume_account", account_id: "zhap-account-2" } as const
const proposal = (id: string, state: AgentProposal["state"], subject: AgentProposal["subject"], path: string | null): AgentProposal => ({
  proposal_id: id, state, subject, digest: "d".repeat(64), created_at: "2026-11-03T20:41:00Z", expires_at: "2026-11-03T21:11:00Z", requested_by: { pid: 4412, path }, outcome: null,
})
const proposals: AgentProposal[] = [
  proposal("p-0123456789ab", "pending", resume, "CopyTrading Assistant"),
  proposal("p-0123456789ac", "pending", { kind: "set_account_limits", account_id: "zhap-account-2", changes: [{ field: "max_order_usd", value: "150" }, { field: "overnight", value: "true" }] }, "/Users/owner/.local/bin/claude"),
  proposal("p-0123456789ad", "succeeded", { kind: "start_processing" }, "CopyTrading Assistant"),
]

const audit: AgentAuditEntry[] = [
  { at: "2026-11-03T20:55:00Z", actor: "agent", caller_pid: 4412, caller_path: "/Users/owner/.local/bin/claude", operation: "list_accounts", tier: "read", outcome: "ok", proposal_id: null },
  { at: "2026-11-03T20:41:00Z", actor: "agent", caller_pid: 4412, caller_path: "/Users/owner/.local/bin/claude", operation: "propose_set_account_limits", tier: "propose", outcome: "proposed", proposal_id: "p-0123456789ac" },
  { at: "2026-11-03T20:30:00Z", actor: "owner", caller_pid: null, caller_path: null, operation: "approve_proposal", tier: null, outcome: "approved", proposal_id: "p-0123456789ad" },
  { at: "2026-11-03T20:12:00Z", actor: "agent", caller_pid: 4412, caller_path: "/Users/owner/.local/bin/claude", operation: "pause_account", tier: "pause", outcome: "cooling_down", proposal_id: null },
  { at: "2026-11-03T19:58:00Z", actor: "agent", caller_pid: 4412, caller_path: "/Users/owner/.local/bin/claude", operation: "get_status", tier: "read", outcome: "locked", proposal_id: null },
]

const pendingRestore: PendingRestoreCandidate = {
  candidate_id: "cand-4f2a9c", previous_generation: "gen-0007", active_generation: "gen-0008", installation_id: "5d3c1b7a-90e2-4c1f-8a77-2f6c0e9b1d44",
  environment_ids: ["paper"], account_ids: ["zhap-account-2"], credential_references: [], candidate_valid: true,
}

const restorePreview: RestorePreview = {
  format_version: 1, created_at: "2026-11-02T18:20:00Z", installation_id: "5d3c1b7a-90e2-4c1f-8a77-2f6c0e9b1d44", matches_installation: true, environment_ids: ["paper"],
  account_ids: ["zhap-account-2"], credential_references: [], staging_id: "stage-81c2d0", members: [],
}

const turn: AssistantTurnPage = {
  turn_id: "t-0123456789ab",
  done: true,
  events: [
    { seq: 1, kind: "step", text: "Read zhap-account-2's history", link: null, proposal_id: null, code: null },
    { seq: 2, kind: "text", text: "The last post, **SOXS sell 40.45**, was copied: a sell of 2.052463 shares filled at $40.45.\n\n- No limit was hit\n- Nothing is waiting for you except one request", link: null, proposal_id: null, code: null },
    { seq: 3, kind: "link", text: null, link: { kind: "account", id: "zhap-account-2", title: "zhap-account-2" }, proposal_id: null, code: null },
    { seq: 4, kind: "step", text: "Asked you to approve copying into zhap-account-2", link: null, proposal_id: null, code: null },
    { seq: 5, kind: "proposal", text: null, link: null, proposal_id: "p-0123456789ab", code: null },
    { seq: 6, kind: "done", text: null, link: null, proposal_id: null, code: null },
  ],
}

// COPYTRADING_FIXTURE_STATE=assistant-error ends the answer with a refused step and an error.
const failedTurn: AssistantTurnPage = {
  turn_id: "t-0123456789ac",
  done: true,
  events: [
    { seq: 1, kind: "step", text: "Couldn't read zhap-account-2's history", link: null, proposal_id: null, code: null },
    { seq: 2, kind: "error", text: "The model did not answer in time. Ask again in a moment.", link: null, proposal_id: null, code: null },
    { seq: 3, kind: "done", text: null, link: null, proposal_id: null, code: null },
  ],
}

// The agent socket and the fills switch change in fixture mode too, so a capture can show either choice.
const agentsProblem = process.env.COPYTRADING_FIXTURE_STATE === "agents-problem"
let agentAccess: AgentAccessState = {
  access: "propose",
  listening: !agentsProblem,
  problem: agentsProblem ? "Agents cannot connect: the agent control socket path is too long for a Unix socket." : null,
}
let fillAlerts = true
let theme: Theme = "dark"
let menuBar: MenuBarMode = "balance"

export const settingsReads: Record<string, (params: Params) => Promise<Result<unknown>>> = {
  getAgentAccess: () => ok(agentAccess),
  getFillAlerts: () => ok(fillAlerts),
  getTheme: () => ok(theme),
  getMenuBar: () => ok(menuBar),
  getSecretStatus: () => ok(secrets),
  getEngineStatus: () => ok(engine),
  readDiagnostics: () => ok({ entries: journal, bytes: 184_320 }),
  listProposals: () => ok(proposals),
  getAgentAudit: () => ok(audit),
  getRestoreCandidate: () => ok(process.env.COPYTRADING_FIXTURE_STATE === "pending-restore" ? pendingRestore : null),
  getAssistantTurn: () => ok(process.env.COPYTRADING_FIXTURE_STATE === "assistant-error" ? failedTurn : turn),
}

export const settingsActs: Record<string, (params: Params) => Promise<Result<unknown>>> = {
  assistantAsk: () => ok({ turn_id: turn.turn_id }),
  assistantCancel: () => ok({ cancelled: true }),
  assistantReset: () => ok(null),
  chooseRestoreArchive: () => ok("/Users/owner/Documents/CopyTrading-Backup.zip"),
  chooseBackupDestination: () => ok("/Users/owner/Documents/CopyTrading-Backup.zip"),
  previewRestore: () => ok(restorePreview),
  activateRestore: () => ok({ status: "restored" }),
  rollbackRestore: () => ok(null),
  setAgentAccess: (params) => {
    const access = params?.access as AgentAccess
    agentAccess = { access, listening: access !== "off", problem: null }
    return ok(agentAccess)
  },
  setFillAlerts: (params) => ok((fillAlerts = params?.on === true)),
  setTheme: (params) => ok((theme = THEMES.find((t) => t === params?.theme) ?? theme)),
  setMenuBar: (params) => ok((menuBar = MENU_BAR_MODES.find((m) => m === params?.mode) ?? menuBar)),
  setSkippedCalls: () => ok(null),
}
