import { AlertCircleIcon } from "@/components/icons/AlertCircleIcon"
import { MinusSignIcon } from "@/components/icons/MinusSignIcon"
import { Tick02Icon } from "@/components/icons/Tick02Icon"
import { Badge } from "@/components/arc/badge/badge"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import { ProposalActions } from "@/features/settings/ProposalActions"
import { statusLine, summary } from "@/features/settings/proposals"
import { useResult } from "@/lib/use-result"
import styles from "./assistant.module.css"

/**
 * Something the assistant asked the owner to approve: what would change, then the one decision it needs.
 * The assistant never approves: Approve asks the owner in a native dialog, and a request only the app can carry out can only be rejected here.
 */
export function AssistantProposalCard({ proposalId }: { proposalId: string }) {
  const proposals = useResult(() => window.copytrading.read.listProposals(), `proposal:${proposalId}`)
  if (proposals.status === "loading") return <Skeleton label="Loading the request" lines={2} />
  if (proposals.status === "error") {
    return (
      <p role="alert" className={styles.proposalHint}>
        {proposals.error}{" "}
        <button type="button" style={{ all: "unset", cursor: "pointer", textDecoration: "underline" }} onClick={proposals.retry}>
          Try again
        </button>
      </p>
    )
  }
  const proposal = proposals.data.find((p) => p.proposal_id === proposalId)
  if (!proposal) return <p className={styles.proposalHint}>A change that needed your approval is no longer waiting.</p>
  const waiting = proposal.state === "pending"
  const done = proposal.state === "succeeded" || proposal.state === "running"
  const failed = proposal.state === "failed" || proposal.state === "outcome_unknown"
  return (
    <div className={styles.proposal}>
      <div className={styles.proposalCard}>
        <p>{waiting ? `${summary(proposal)}?` : summary(proposal)}</p>
        {waiting && <p className={styles.proposalHint}>{statusLine(proposal)}</p>}
      </div>
      {waiting ? (
        <ProposalActions proposal={proposal} gate onDecided={() => proposals.retry()} />
      ) : (
        <Badge tone={done ? "info" : failed ? "danger" : "neutral"} outline={!done && !failed} className={styles.proposalStatus} icon={done ? <Tick02Icon width={16} height={16} aria-hidden="true" /> : failed ? <AlertCircleIcon width={16} height={16} aria-hidden="true" /> : <MinusSignIcon width={16} height={16} aria-hidden="true" />}>
          {statusLine(proposal)}
        </Badge>
      )}
    </div>
  )
}
