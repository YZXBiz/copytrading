import { useMemo, useState } from "react"
import type { AgentAuditEntry, AgentProposal } from "../../../shared/contract"
import { AgentApprovals, type ApprovalDecision, type ApprovalRequest, type DecisionResult, type ResolvedEntry } from "@/components/arc/blocks/agent-approvals/agent-approvals"
import { readClock } from "@/lib/clock"
import { ago, dateTime } from "@/lib/format"
import { type Loaded, useResult } from "@/lib/use-result"
import { Note, type NoteState } from "./Note"
import { SectionError } from "./SectionError"
import { SectionSkeleton } from "./SettingsSection"
import { accountOf, auditOutcome, auditWhen, auditWho, callerName, canApprove, isLive, limitRows, resultMessage, summary } from "./proposals"
import { humanCode } from "./words"

const AUDIT_SHOWN = 10

/** The recent list names how a request ended in the old badge tones; the log draws them as icons. */
const logTone = { success: "done", secondary: "waiting", warning: "stopped", destructive: "failed", outline: "stopped" } as const

/** What was read last stays on screen while it is read again, so a decision does not tear down the card that shows its outcome. */
function useKept<T>(loaded: Loaded<T>): Loaded<T> {
  const [kept, setKept] = useState<T | null>(null)
  if (loaded.status === "ready" && loaded.data !== kept) setKept(loaded.data)
  return loaded.status === "loading" && kept !== null ? { status: "ready", data: kept } : loaded
}

const unsupported = "This changes the saved setup, which this version cannot apply yet. You can reject it."

/**
 * What agents and the assistant asked for, waiting for the owner, and what became of the recent ones. Approve is a
 * confirmed action: main asks the owner in a native dialog, so a Cancel there sends nothing and the request stays.
 */
export function AgentRequests() {
  const proposals = useResult(() => window.copytrading.read.listProposals(), "proposals")
  const setup = useResult(() => window.copytrading.read.getSetup(), "setup")
  // A decision adds to the recent list, so it is read again after one.
  const [decisions, setDecisions] = useState(0)
  const audit = useResult(() => window.copytrading.read.getAgentAudit({ limit: 20 }), `agent-audit:${decisions}`)
  // What became of an approval that did not finish stays above the card: the request leaves the queue.
  const [problem, setProblem] = useState<NoteState | null>(null)

  const waiting = useKept(proposals)
  const recent = useKept(audit)
  const configuration = setup.status === "ready" ? (setup.data?.configuration ?? null) : null

  const pendingRead = waiting.status === "ready" ? waiting.data : null
  const recentRead = recent.status === "ready" ? recent.data : null

  const requests = useMemo<ApprovalRequest[]>(() => {
    const now = readClock()
    return (pendingRead ?? [])
      .filter((p: AgentProposal) => p.state === "pending")
      .map((p) => ({
        id: p.proposal_id,
        agent: { id: p.requested_by.path ?? "unknown", name: callerName(p.requested_by.path) },
        title: summary(p),
        reason: canApprove(p) ? undefined : unsupported,
        args: [
          ...limitRows(p, configuration).map((row) => ({ key: row.title, label: row.title, value: row.after, before: row.now })),
          { key: "expires", label: "Expires", value: dateTime(p.expires_at) },
        ],
        live: Boolean(accountOf(p)) && isLive(p, configuration),
        readOnly: !canApprove(p),
        when: ago(p.created_at, now),
        requestedAt: p.created_at,
      }))
  }, [pendingRead, configuration])

  const resolved = useMemo<ResolvedEntry[]>(() => {
    const now = readClock()
    const seen = new Map<string, number>()
    return (recentRead ?? []).slice(0, AUDIT_SHOWN).map((entry: AgentAuditEntry) => {
      const outcome = auditOutcome(entry)
      const base = `${entry.at}:${entry.operation}:${entry.outcome}`
      const count = seen.get(base) ?? 0
      seen.set(base, count + 1)
      return { id: `${base}:${count}`, summary: humanCode(entry.operation), outcome: outcome.text, tone: logTone[outcome.tone], by: auditWho(entry), when: auditWhen(entry, now), at: entry.at }
    })
  }, [recentRead])

  async function decide({ requestId, outcome }: ApprovalDecision): Promise<DecisionResult> {
    const { act } = window.copytrading
    const result = await (outcome === "approved" ? act.approveProposal({ proposal_id: requestId }) : act.rejectProposal({ proposal_id: requestId }))
    if (!result.ok) {
      // A Cancel in the dialog changes nothing and says nothing.
      if (result.cancelled) return { status: "cancelled" }
      throw new Error(result.error)
    }
    // Where the request ended up (done, failed, not confirmed yet) is told by the engine; the list reads again for the log.
    const note = outcome === "approved" ? resultMessage(result.value) : undefined
    const finished = note === undefined || note.startsWith("Done")
    setProblem(finished ? null : { kind: "problem", text: note })
    setDecisions((n) => n + 1)
    proposals.retry()
    return { status: "done", note, problem: !finished }
  }

  if (waiting.status === "loading" || recent.status === "loading") return <SectionSkeleton rows={3} label="Loading requests" />
  if (waiting.status === "error") return <SectionError title="Requests did not load" message={waiting.error} onRetry={proposals.retry} />
  if (recent.status === "error") return <SectionError title="Recent requests did not load" message={recent.error} onRetry={audit.retry} />

  return (
    <>
      {problem && <Note note={problem} />}
      <AgentApprovals requests={requests} resolved={resolved} hint="Approve only what you asked for." onDecision={decide} />
    </>
  )
}
