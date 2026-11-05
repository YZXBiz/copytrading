import { Activity01Icon } from "@/components/icons/Activity01Icon"
import { Link01Icon } from "@/components/icons/Link01Icon"
import { RefreshIcon } from "@/components/icons/RefreshIcon"
import type { AccountOverview } from "../../../shared/contract"
import { Badge } from "@/components/arc/badge/badge"
import { Button } from "@/components/arc/button/button"
import { DropdownMenu } from "@/components/arc/dropdown-menu/dropdown-menu"
import { navigate } from "@/features/shell/route"
import styles from "./account.module.css"
import { type AccountControl, ControlButton } from "./AccountControl"
import { COPYING_TITLE, badgeTone, isWarning } from "./copying"

/** The account's name and state, its secondary actions, and the page's one primary action: Stop or Start copying. */
export function AccountHeader({
  account,
  guru,
  control,
  canEditLimits,
  onEditLimits,
  onRefresh,
  onOpenConnections,
}: {
  account: AccountOverview
  /** The guru this account copies, once the limits have loaded. */
  guru: string | null
  control: AccountControl
  canEditLimits: boolean
  onEditLimits: () => void
  onRefresh: () => void
  onOpenConnections: () => void
}) {
  const { state } = control
  const subtitle = state.detail ?? (guru ? `Copies ${guru}` : null)
  return (
    <header className={styles.header}>
      <div className={styles.identity}>
        <h1 className={styles.title}>{account.account_id}</h1>
        <div className={styles.badges}>
          <Badge tone={account.environment === "paper" ? "neutral" : "warning"}>{account.environment === "paper" ? "Paper" : "Live"}</Badge>
          <Badge tone={badgeTone(state)} dot>
            {COPYING_TITLE[state.word]}
          </Badge>
          {subtitle && <span className={state.detail && isWarning(state) ? styles.subtitleWarn : styles.subtitle}>{subtitle}</span>}
        </div>
      </div>
      <div className={styles.actions}>
        <Button type="button" variant="secondary" disabled={!canEditLimits} onClick={onEditLimits}>
          Edit limits
        </Button>
        <DropdownMenu
          label="More"
          items={[
            { label: "Refresh", icon: <RefreshIcon width={16} height={16} />, onSelect: onRefresh },
            { label: "View in Activity", icon: <Activity01Icon width={16} height={16} />, onSelect: () => navigate("activity") },
            { label: "Open Connections", icon: <Link01Icon width={16} height={16} />, onSelect: onOpenConnections },
          ]}
        />
        <ControlButton control={control} />
      </div>
    </header>
  )
}
