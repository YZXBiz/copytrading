/** Types for Agent approvals. The caller passes what the app already reads, worded and formatted for the screen. */

export interface ApprovalAgent {
  id: string;
  /** Who asked, such as "Claude Code" or "Assistant". */
  name: string;
}

/** One line of what the request would change. `before` set draws it as "before → value". */
export interface ApprovalArgument {
  key: string;
  label: string;
  value: string;
  before?: string;
}

export interface ApprovalRequest {
  id: string;
  agent: ApprovalAgent;
  /** The request in plain words, shown large. */
  title: string;
  /** One quiet line under the title. */
  reason?: string;
  args: ApprovalArgument[];
  /** The request could touch real money: a live account. */
  live?: boolean;
  /** Only the app can carry this out, so it can be rejected here but not approved. */
  readOnly?: boolean;
  /** When it arrived, as the screen words it: "5 min ago". */
  when: string;
  /** ISO time it arrived, for the time element. */
  requestedAt: string;
}

export type ApprovalOutcome = "approved" | "rejected";

export interface ApprovalDecision {
  requestId: string;
  outcome: ApprovalOutcome;
}

/** What the caller reports back once the decision has been made. A cancelled confirmation changes nothing. */
export type DecisionResult = { status: "done"; note?: string; problem?: boolean } | { status: "cancelled" };

/** A recorded request or decision, newest first. */
export interface ResolvedEntry {
  id: string;
  summary: string;
  /** How it ended, in words: "Done", "Waiting for you", "Refused". */
  outcome: string;
  tone: "done" | "waiting" | "stopped" | "failed";
  /** Who made it: "You", or the agent's name. */
  by: string;
  /** When, as the screen words it. */
  when: string;
  /** ISO time, for the time element. */
  at: string;
}
