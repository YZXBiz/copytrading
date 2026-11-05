import { useState } from "react"
import { Cancel01Icon } from "@/components/icons/Cancel01Icon"
import { Tick02Icon } from "@/components/icons/Tick02Icon"
import type { AgentProposal } from "../../../shared/contract"
import { Button } from "@/components/arc/button/button"
import { canApprove, resultMessage } from "./proposals"
import styles from "./settings.module.css"

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
    <div className={gate ? styles.gate : styles.proposalActions}>
      {/* Approve is the only primary button; Reject sits beside it, equal width in the assistant's gate. */}
      <div className={styles.proposalButtons}>
        <Button type="button" size="sm" variant="secondary" disabled={working} onClick={() => decide(false)}>
          {gate && <Cancel01Icon width={16} height={16} aria-hidden="true" />}
          Reject
        </Button>
        {canApprove(proposal) && (
          <Button type="button" size="sm" loading={working} onClick={() => decide(true)}>
            {gate && <Tick02Icon width={16} height={16} aria-hidden="true" />}
            Approve
          </Button>
        )}
      </div>
      {message && (
        <p role="status" className={styles.proposalMessage}>
          {message}
        </p>
      )}
    </div>
  )
}
