import { useState } from "react"
import type { AgentProposal } from "../../../shared/contract"
import { Button } from "@/components/ui/button"
import { canApprove, resultMessage } from "./proposals"

/**
 * Approve and Reject for one waiting request. Approving shows a native confirmation from main, which words it from what the
 * engine holds, so a Cancel there sends nothing. A request only the app can carry out (a setup change) can only be rejected.
 */
export function ProposalActions({ proposal, onDecided }: { proposal: AgentProposal; onDecided: (outcome: string | null) => void }) {
  const [working, setWorking] = useState(false)
  const [message, setMessage] = useState<string | null>(null)

  async function decide(approve: boolean) {
    setWorking(true)
    setMessage(null)
    const { act } = window.copytrading
    const result = await (approve ? act.approveProposal({ proposal_id: proposal.proposal_id }) : act.rejectProposal({ proposal_id: proposal.proposal_id }))
    setWorking(false)
    if (!result.ok) {
      if (!result.cancelled) setMessage(result.error)
      return
    }
    // Where the request ended up (done, failed, not confirmed yet) is told by the caller, whose list drops this row.
    onDecided(approve ? resultMessage(result.value) : null)
  }

  return (
    <div className="flex flex-col items-end gap-1">
      <div className="flex gap-2">
        <Button type="button" size="sm" variant="outline" disabled={working} onClick={() => decide(false)}>
          Reject
        </Button>
        {canApprove(proposal) && (
          <Button type="button" size="sm" disabled={working} onClick={() => decide(true)}>
            Approve…
          </Button>
        )}
      </div>
      {message && (
        <p role="status" className="text-muted-foreground max-w-64 text-right text-xs">
          {message}
        </p>
      )}
    </div>
  )
}
