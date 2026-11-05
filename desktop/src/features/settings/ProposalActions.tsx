import { useState } from "react"
import { Cancel01Icon } from "@/components/icons/Cancel01Icon"
import { Tick02Icon } from "@/components/icons/Tick02Icon"
import type { AgentProposal } from "../../../shared/contract"
import { Button } from "@/components/ui/button"
import { canApprove, resultMessage } from "./proposals"

/**
 * Approve and Reject for one waiting request. Approving shows a native confirmation from main, which words it from what the
 * engine holds, so a Cancel there sends nothing. A request only the app can carry out (a setup change) can only be rejected.
 */
export function ProposalActions({ proposal, onDecided, gate = false }: { proposal: AgentProposal; onDecided: (outcome: string | null) => void; gate?: boolean }) {
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
    <div className={gate ? "flex flex-col gap-1.5" : "flex flex-col items-end gap-1"}>
      {/* The assistant's approval gate: equal-width buttons, Approve the only primary one (ai-chat-8's plan turn). */}
      <div className={gate ? "flex gap-2 *:flex-1" : "flex gap-2"}>
        <Button type="button" size={gate ? "default" : "sm"} variant="outline" className={gate ? "gap-1.5" : undefined} disabled={working} onClick={() => decide(false)}>
          {gate && <Cancel01Icon aria-hidden="true" />}
          Reject
        </Button>
        {canApprove(proposal) && (
          <Button type="button" size={gate ? "default" : "sm"} className={gate ? "gap-1.5" : undefined} disabled={working} onClick={() => decide(true)}>
            {gate && <Tick02Icon aria-hidden="true" />}
            Approve…
          </Button>
        )}
      </div>
      {message && (
        <p role="status" className={gate ? "text-muted-foreground text-xs" : "text-muted-foreground max-w-64 text-right text-xs"}>
          {message}
        </p>
      )}
    </div>
  )
}
