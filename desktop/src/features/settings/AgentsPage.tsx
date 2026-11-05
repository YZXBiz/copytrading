import { useState } from "react"
import type { AgentAuditEntry, AgentProposal, TradingConfiguration } from "../../../shared/contract"
import { Meta } from "@/components/meta"
import { Badge } from "@/components/arc/badge/badge"
import { readClock } from "@/lib/clock"
import { dateTime } from "@/lib/format"
import { useResult } from "@/lib/use-result"
import { AgentAccess } from "./AgentAccess"
import { Note } from "./Note"
import { SectionError } from "./SectionError"
import { ProposalActions } from "./ProposalActions"
import { SettingsRow } from "./SettingsRow"
import styles from "./settings.module.css"
import { SectionSkeleton, SettingsSection } from "./SettingsSection"
import { accountOf, auditWhen, auditWho, auditOutcome, callerName, canApprove, isLive, limitRows, summary } from "./proposals"
import { humanCode } from "./words"

const AUDIT_SHOWN = 10

/** The audit list names tones in the old badge words; these are the new badge's. */
const outcomeTone = (tone: string) => (tone === "success" ? "info" : tone === "warning" ? "warning" : tone === "destructive" ? "danger" : "neutral")

function ProposalRow({ proposal, setup, onDecided }: { proposal: AgentProposal; setup: TradingConfiguration | null; onDecided: (outcome: string | null) => void }) {
  const rows = limitRows(proposal, setup)
  const lines = [
    ...rows.map((row) => `${row.title}: ${row.now} → ${row.after}`),
    callerName(proposal.requested_by.path),
    `Expires ${dateTime(proposal.expires_at)}`,
    ...(canApprove(proposal) ? [] : ["This changes the saved setup, which this version cannot apply yet. You can reject it."]),
  ]
  return (
    <div className={styles.proposal}>
      <div className={styles.rowText}>
        <h4>
          {summary(proposal)}
          {accountOf(proposal) && isLive(proposal, setup) && <Badge tone="warning">Live</Badge>}
        </h4>
        <div className={styles.rowDescription}>
          <Meta text={lines.join("\n")} />
        </div>
      </div>
      <ProposalActions proposal={proposal} onDecided={onDecided} />
    </div>
  )
}

/** What agents and the assistant asked for, waiting for the owner. Approve is a confirmed action; nothing happens until then. */
function Waiting({ onDecided }: { onDecided: () => void }) {
  const proposals = useResult(() => window.copytrading.read.listProposals(), "proposals")
  const setup = useResult(() => window.copytrading.read.getSetup(), "setup")
  // What became of the last request the owner approved: the row leaves the list, so its outcome is kept here.
  const [outcome, setOutcome] = useState<string | null>(null)
  if (proposals.status === "loading") return <SectionSkeleton rows={2} label="Loading" />
  if (proposals.status === "error") return <SectionError title="Requests did not load" message={proposals.error} onRetry={proposals.retry} />
  const waiting = proposals.data.filter((p) => p.state === "pending")
  const configuration = setup.status === "ready" ? (setup.data?.configuration ?? null) : null
  const decided = (result: string | null) => {
    setOutcome(result)
    proposals.retry()
    onDecided()
  }
  return (
    <>
      {outcome && <Note note={{ kind: outcome.startsWith("Done") ? "done" : "problem", text: outcome }} />}
      <SettingsSection title="Waiting for you" hint="Approve only what you asked for.">
        {waiting.length === 0 ? (
          <SettingsRow title="Nothing is waiting" />
        ) : (
          waiting.map((proposal) => <ProposalRow key={proposal.proposal_id} proposal={proposal} setup={configuration} onDecided={decided} />)
        )}
      </SettingsSection>
    </>
  )
}

function AuditRow({ entry, now }: { entry: AgentAuditEntry; now: Date }) {
  const outcome = auditOutcome(entry)
  return (
    <SettingsRow title={humanCode(entry.operation)} description={auditWho(entry)}>
      <span className={styles.valueMuted}>{auditWhen(entry, now)}</span>
      <Badge tone={outcomeTone(outcome.tone)}>{outcome.text}</Badge>
    </SettingsRow>
  )
}

/** The newest recorded requests and owner decisions. */
function Recent({ version }: { version: number }) {
  const audit = useResult(() => window.copytrading.read.getAgentAudit({ limit: 20 }), `agent-audit:${version}`)
  if (audit.status === "loading") return <SectionSkeleton rows={2} label="Loading" />
  if (audit.status === "error") return <SectionError title="Recent requests did not load" message={audit.error} onRetry={audit.retry} />
  const now = readClock()
  return (
    <SettingsSection title="Recent requests">
      {audit.data.length === 0 ? (
        <SettingsRow title="No requests yet" />
      ) : (
        audit.data.slice(0, AUDIT_SHOWN).map((entry, index) => <AuditRow key={index} entry={entry} now={now} />)
      )}
    </SettingsSection>
  )
}

/** Requests from the assistant and from agents, and what happened to them. */
export function AgentsPage() {
  // A decision adds to the recent list, so it is read again after one.
  const [decisions, setDecisions] = useState(0)
  return (
    <div className={styles.page}>
      <AgentAccess />
      <Waiting onDecided={() => setDecisions((n) => n + 1)} />
      <Recent version={decisions} />
    </div>
  )
}
