import { AlertCircleIcon } from "@/components/icons/AlertCircleIcon"
import { MinusSignIcon } from "@/components/icons/MinusSignIcon"
import { Tick02Icon } from "@/components/icons/Tick02Icon"
import { Badge } from "@/components/reui/badge"
import { Bubble, BubbleContent } from "@/components/ui/bubble"
import { Skeleton } from "@/components/ui/skeleton"
import { ProposalActions } from "@/features/settings/ProposalActions"
import { statusLine, summary } from "@/features/settings/proposals"
import { useResult } from "@/lib/use-result"

/**
 * Something the assistant asked the owner to approve, as ai-chat-8's plan turn: what would change, then the one decision it needs.
 * The assistant never approves: Approve asks the owner in a native dialog, and a request only the app can carry out can only be rejected here.
 */
export function AssistantProposalCard({ proposalId }: { proposalId: string }) {
  const proposals = useResult(() => window.copytrading.read.listProposals(), `proposal:${proposalId}`)
  if (proposals.status === "loading") return <Skeleton role="status" aria-label="Loading the request" className="h-24 w-full" />
  if (proposals.status === "error") {
    return (
      <p role="alert" className="text-warning-foreground dark:text-warning text-xs">
        {proposals.error}{" "}
        <button type="button" className="underline" onClick={proposals.retry}>
          Retry
        </button>
      </p>
    )
  }
  const proposal = proposals.data.find((p) => p.proposal_id === proposalId)
  if (!proposal) return <p className="text-muted-foreground text-xs">A change that needed your approval is no longer waiting.</p>
  const waiting = proposal.state === "pending"
  const done = proposal.state === "succeeded" || proposal.state === "running"
  const failed = proposal.state === "failed" || proposal.state === "outcome_unknown"
  return (
    <div className="flex flex-col gap-2.5">
      <Bubble variant="outline" className="max-w-full">
        <BubbleContent className="flex flex-col gap-1">
          <p className="text-sm leading-relaxed">{waiting ? `${summary(proposal)}?` : summary(proposal)}</p>
          {waiting && <p className="text-muted-foreground text-xs">{statusLine(proposal)}</p>}
        </BubbleContent>
      </Bubble>
      {waiting ? (
        <ProposalActions proposal={proposal} gate onDecided={() => proposals.retry()} />
      ) : (
        <Badge variant={done ? "success-light" : failed ? "destructive-light" : "outline"} className="w-fit gap-1">
          {done ? <Tick02Icon aria-hidden="true" /> : failed ? <AlertCircleIcon aria-hidden="true" /> : <MinusSignIcon aria-hidden="true" />}
          {statusLine(proposal)}
        </Badge>
      )}
    </div>
  )
}
