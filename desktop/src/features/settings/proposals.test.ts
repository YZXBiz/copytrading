import { describe, expect, it } from "vitest"
import type { AgentAuditEntry, AgentProposal, TradingConfiguration } from "../../../shared/contract"
import { accountOf, auditLine, auditOutcome, callerName, canApprove, isLive, limitRows, resultMessage, statusLine, summary } from "./proposals"

const proposal = (subject: AgentProposal["subject"], over: Partial<AgentProposal> = {}): AgentProposal => ({
  proposal_id: "p-0123456789ab", state: "pending", subject, digest: "d", created_at: "2026-11-03T14:00:00Z", expires_at: "2026-11-03T14:10:00Z",
  requested_by: { pid: null, path: "CopyTrading Assistant" }, outcome: null, ...over,
})

const setup = { accounts: [{ id: "a1", environment: "paper", policy: { max_order_usd: "500", approve_orders: false } }, { id: "a2", environment: "live", policy: {} }] } as unknown as TradingConfiguration

describe("summary", () => {
  it("says what approving does, for every kind", () => {
    expect(summary(proposal({ kind: "resume_account", account_id: "a1" }))).toBe("Start copying into a1")
    expect(summary(proposal({ kind: "set_recovery", account_id: "a1", preference: "manual" }))).toBe("In a1, after a restart: Wait for me")
    expect(summary(proposal({ kind: "start_processing" }))).toBe("Start copying")
    expect(summary(proposal({ kind: "apply_setup" }))).toBe("Apply the setup, with live accounts")
    expect(summary(proposal({ kind: "set_account_limits", account_id: "a1", changes: [{ field: "max_order_usd", value: "750" }, { field: "overnight", value: "true" }] })))
      .toBe("In a1: Largest single buy $750, Trade overnight On")
  })
  it("words a limit order by its price and a market order by its type", () => {
    const order = { kind: "confirm_manual_order", account_id: "a1", preview_id: "x", environment: "paper", symbol: "F", side: "buy", order_type: "limit", quantity: "10", limit_price: "12.3" } as const
    expect(summary(proposal(order))).toBe("Buy 10 F, limit $12.30, in a1")
    expect(summary(proposal({ ...order, limit_price: null, order_type: "market" }))).toBe("Buy 10 F, market, in a1")
  })
})

describe("who and what", () => {
  it("finds the account, and whether it is live", () => {
    expect(accountOf(proposal({ kind: "start_processing" }))).toBeNull()
    expect(accountOf(proposal({ kind: "resume_account", account_id: "a2" }))).toBe("a2")
    expect(isLive(proposal({ kind: "resume_account", account_id: "a2" }), setup)).toBe(true)
    expect(isLive(proposal({ kind: "resume_account", account_id: "a1" }), setup)).toBe(false)
    expect(isLive(proposal({ kind: "apply_setup" }), null)).toBe(true)
  })
  it("lets the owner approve only what the engine finishes itself", () => {
    expect(canApprove(proposal({ kind: "resume_account", account_id: "a1" }))).toBe(true)
    expect(canApprove(proposal({ kind: "set_account_limits", account_id: "a1", changes: [] }))).toBe(false)
    expect(canApprove(proposal({ kind: "start_processing" }))).toBe(false)
  })
  it("shows each limit now and after, and a dash when the setup does not say", () => {
    const rows = limitRows(proposal({ kind: "set_account_limits", account_id: "a1", changes: [{ field: "max_order_usd", value: "750" }, { field: "approve_orders", value: "true" }, { field: "poll_seconds", value: "5" }] }), setup)
    expect(rows).toEqual([
      { title: "Largest single buy", now: "$500", after: "$750" },
      { title: "Ask me before sending orders", now: "Off", after: "On" },
      { title: "Check for posts every (seconds)", now: "—", after: "5" },
    ])
  })
  it("names a caller by its program, never its path", () => {
    expect(callerName("CopyTrading Assistant")).toBe("CopyTrading Assistant")
    expect(callerName("/usr/local/bin/claude")).toBe("claude")
    expect(callerName(null)).toBe("An unknown program")
  })
})

describe("how a request stands", () => {
  it("says where it is", () => {
    expect(statusLine(proposal({ kind: "start_processing" }))).toBe("Waiting for your approval")
    expect(statusLine(proposal({ kind: "start_processing" }, { state: "outcome_unknown" }))).toBe("Outcome unknown")
  })
  it("reports the result with the engine's code in words", () => {
    expect(resultMessage(proposal({ kind: "start_processing" }, { state: "failed", outcome: { status: "failed", code: "keys_missing" } }))).toBe("Could not complete: Start copying (Keys missing).")
    expect(resultMessage(proposal({ kind: "start_processing" }, { state: "succeeded" }))).toBe("Done: Start copying.")
  })
})

describe("audit", () => {
  const entry = (over: Partial<AgentAuditEntry>): AgentAuditEntry => ({ at: "2026-11-03T13:55:00Z", actor: "agent", caller_pid: 1, caller_path: "/bin/claude", operation: "list_accounts", tier: null, outcome: "ok", proposal_id: null, ...over })
  it("colours how it ended", () => {
    expect(auditOutcome(entry({}))).toEqual({ text: "Done", tone: "success" })
    expect(auditOutcome(entry({ outcome: "proposed" }))).toEqual({ text: "Waiting for you", tone: "secondary" })
    expect(auditOutcome(entry({ outcome: "cooling_down" }))).toEqual({ text: "Cooling down", tone: "warning" })
    expect(auditOutcome(entry({ outcome: "conflict" })).tone).toBe("destructive")
    expect(auditOutcome(entry({ outcome: "whatever" })).tone).toBe("outline")
  })
  it("says who and when", () => {
    const now = new Date("2026-11-03T14:00:00Z")
    expect(auditLine(entry({}), now)).toBe("claude · 5 min ago")
    expect(auditLine(entry({ actor: "owner" }), now)).toBe("You · 5 min ago")
  })
})
