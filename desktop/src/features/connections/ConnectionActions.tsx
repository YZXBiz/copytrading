import { useReducedMotion } from "motion/react"
import { Button } from "@/components/arc/button/button"
import { ConnectControl, type ConnectStatus } from "@/components/arc/blocks/integrations/connect-control"

/** What can be done with one connection: Connect (which checks it), then Edit. A row with nothing to check, such as a guru, only has Edit. */
export function ConnectionActions({
  label,
  onEdit,
  onConnect,
  connectLabel = "Connect",
  connection = "idle",
}: {
  /** Names the row for the buttons' accessible names, such as "Discord". */
  label: string
  onEdit: () => void
  /** Absent for a row with nothing to check. */
  onConnect?: () => void
  connectLabel?: string
  /** Where the check is: not run, running, or passed. */
  connection?: ConnectStatus
}) {
  const reduce = !!useReducedMotion()
  return (
    <>
      {onConnect && <ConnectControl name={label} status={connection} reduce={reduce} idleLabel={connectLabel} onConnect={onConnect} />}
      <Button type="button" size="sm" variant="ghost" onClick={onEdit} aria-label={`Edit ${label}`}>
        Edit
      </Button>
    </>
  )
}
