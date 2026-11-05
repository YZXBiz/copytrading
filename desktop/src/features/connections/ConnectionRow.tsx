import { useReducedMotion } from "motion/react"
import type { Icon } from "@/lib/icon"
import { Button } from "@/components/arc/button/button"
import { ConnectControl, type ConnectStatus } from "@/components/arc/blocks/integrations/connect-control"
import { StatusBadge } from "./StatusBadge"
import type { Status } from "./state"
import styles from "./connections.module.css"

/** One service, account or guru in Connections: its mark, name and status, one line of detail, then Connect and Edit. */
export function ConnectionRow({
  icon: Icon,
  title,
  detail,
  status,
  problem,
  onEdit,
  onConnect,
  connectLabel = "Connect",
  connection = "idle",
  label,
}: {
  icon: Icon
  title: string
  detail?: string
  status: Status
  /** Why the last check failed, in words. */
  problem?: string | null
  onEdit: () => void
  /** Absent for a row with nothing to check, such as a guru. */
  onConnect?: () => void
  connectLabel?: string
  /** Where the check is: not run, running, or passed. */
  connection?: ConnectStatus
  /** Names the row for the buttons' accessible names, such as "Discord". */
  label: string
}) {
  const reduce = !!useReducedMotion()
  return (
    <li className={styles.row}>
      <Icon className={styles.rowIcon} width={20} height={20} aria-hidden="true" />
      <div className={styles.rowBody}>
        <div className={styles.rowTitle}>
          <span>{title}</span>
          <StatusBadge status={status} />
        </div>
        {detail && <p className={styles.rowDetail}>{detail}</p>}
        {problem && <p className={styles.rowProblem}>{problem}</p>}
      </div>
      <div className={styles.rowActions}>
        {onConnect && <ConnectControl name={label} status={connection} reduce={reduce} idleLabel={connectLabel} onConnect={onConnect} />}
        <Button type="button" size="sm" variant="ghost" onClick={onEdit} aria-label={`Edit ${label}`}>
          Edit
        </Button>
      </div>
    </li>
  )
}
