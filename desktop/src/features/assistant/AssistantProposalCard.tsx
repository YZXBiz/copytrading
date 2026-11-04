import { HandIcon, MinusCircleIcon } from "lucide-react"
import { CheckCircle2Icon } from "lucide-react"
import { Skeleton } from "@/components/ui/skeleton"
import { useResult } from "@/lib/use-result"
import { ProposalActions } from "@/features/settings/ProposalActions"
import { statusLine, summary } from "@/features/settings/proposals"

/**
 * Something the assistant asked the owner to approve. The assistant never approves: Approve asks the owner in a native dialog,
 * and a request only the app can carry out can only be rejected here.
 */
export function AssistantProposalCard({ proposalId }: { proposalId: string }) {
  const proposals = useResult(() => window.copytrading.read.listProposals(), `proposal:${proposalId}`)
  if (proposals.status === "loading") return <Skeleton className="h-16 w-full" />
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
  const Icon = waiting ? HandIcon : proposal.state === "succeeded" || proposal.state === "running" ? CheckCircle2Icon : MinusCircleIcon
  return (
    <div className="flex flex-col gap-2 rounded-lg border p-3">
      <div className="text-muted-foreground flex items-center gap-1.5 text-xs font-medium">
        <Icon className={waiting ? "text-warning-foreground dark:text-warning size-3" : "size-3"} aria-hidden />
        {statusLine(proposal)}
      </div>
      <p className="text-sm font-medium">{waiting ? `${summary(proposal)}?` : summary(proposal)}</p>
      {waiting && <ProposalActions proposal={proposal} onDecided={proposals.retry} />}
    </div>
  )
}
