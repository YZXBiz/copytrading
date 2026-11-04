import type { AgentAuditEntry, AgentProposal, TradingConfiguration } from "../../../shared/contract"
import { RegionError } from "@/components/region-error"
import { Badge } from "@/components/reui/badge"
import { Skeleton } from "@/components/ui/skeleton"
import { Item, ItemActions, ItemContent, ItemDescription, ItemTitle } from "@/components/ui/item"
import { readClock } from "@/lib/clock"
import { dateTime } from "@/lib/format"
import { useResult } from "@/lib/use-result"
import { ProposalActions } from "./ProposalActions"
import { SettingsRow } from "./SettingsRow"
import { SettingsSection } from "./SettingsSection"
import { accountOf, auditLine, auditOutcome, callerName, canApprove, isLive, limitRows, summary } from "./proposals"
import { humanCode } from "./words"

const AUDIT_SHOWN = 10

function ProposalRow({ proposal, setup, onDecided }: { proposal: AgentProposal; setup: TradingConfiguration | null; onDecided: () => void }) {
  const rows = limitRows(proposal, setup)
  const lines = [
    ...rows.map((row) => `${row.title}: ${row.now} → ${row.after}`),
    `${callerName(proposal.requested_by.path)} · expires ${dateTime(proposal.expires_at)}`,
    ...(canApprove(proposal) ? [] : ["This changes the saved setup, which this version cannot apply yet. You can reject it."]),
  ]
  return (
    <Item size="sm" className="rounded-none border-0">
      <ItemContent>
        <ItemTitle>
          {summary(proposal)}
          {accountOf(proposal) && isLive(proposal, setup) && <Badge variant="warning-light">Live</Badge>}
        </ItemTitle>
        <ItemDescription className="line-clamp-none whitespace-pre-line">{lines.join("\n")}</ItemDescription>
      </ItemContent>
      <ItemActions>
        <ProposalActions proposal={proposal} onDecided={onDecided} />
      </ItemActions>
    </Item>
  )
}

/** What agents and the assistant asked for, waiting for the owner. Approve is a confirmed action; nothing happens until then. */
function Waiting() {
  const proposals = useResult(() => window.copytrading.read.listProposals(), "proposals")
  const setup = useResult(() => window.copytrading.read.getSetup(), "setup")
  if (proposals.status === "loading") return <Skeleton className="h-24 w-full" />
  if (proposals.status === "error") return <RegionError title="Requests did not load" message={proposals.error} onRetry={proposals.retry} />
  const waiting = proposals.data.filter((p) => p.state === "pending")
  const configuration = setup.status === "ready" ? (setup.data?.configuration ?? null) : null
  return (
    <SettingsSection title="Waiting for You" hint="Approve only if you asked for this. Agents read messages written by other people, so a request can come from text you have never seen.">
      {waiting.length === 0 ? (
        <SettingsRow title="Nothing is waiting" description="When the assistant or an agent asks for something that could trade, it waits here for you." />
      ) : (
        waiting.map((proposal) => <ProposalRow key={proposal.proposal_id} proposal={proposal} setup={configuration} onDecided={proposals.retry} />)
      )}
    </SettingsSection>
  )
}

function AuditRow({ entry, now }: { entry: AgentAuditEntry; now: Date }) {
  const outcome = auditOutcome(entry)
  return (
    <SettingsRow title={humanCode(entry.operation)} description={auditLine(entry, now)}>
      <Badge variant={outcome.tone === "outline" ? "outline" : outcome.tone === "secondary" ? "secondary" : `${outcome.tone}-light`}>{outcome.text}</Badge>
    </SettingsRow>
  )
}

/** The newest recorded requests and owner decisions. */
function Recent() {
  const audit = useResult(() => window.copytrading.read.getAgentAudit({ limit: 20 }), "agent-audit")
  if (audit.status === "loading") return <Skeleton className="h-24 w-full" />
  if (audit.status === "error") return <RegionError title="Recent requests did not load" message={audit.error} onRetry={audit.retry} />
  const now = readClock()
  return (
    <SettingsSection title="Recent Requests">
      {audit.data.length === 0 ? (
        <SettingsRow title="No requests yet" description="What the assistant and agents ask for, and what you decide, is listed here." />
      ) : (
        audit.data.slice(0, AUDIT_SHOWN).map((entry, index) => <AuditRow key={index} entry={entry} now={now} />)
      )}
    </SettingsSection>
  )
}

/** Requests from the assistant and from agents, and what happened to them. */
export function AgentsPage() {
  return (
    <div className="flex flex-col gap-6">
      <Waiting />
      <Recent />
    </div>
  )
}
