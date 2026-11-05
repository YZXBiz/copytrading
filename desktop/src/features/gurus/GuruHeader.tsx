import { Activity01Icon } from "@/components/icons/Activity01Icon"
import { Link01Icon } from "@/components/icons/Link01Icon"
import { RefreshIcon } from "@/components/icons/RefreshIcon"
import { Badge, type BadgeTone } from "@/components/arc/badge/badge"
import { Breadcrumb } from "@/components/arc/breadcrumb/breadcrumb"
import { DropdownMenu } from "@/components/arc/dropdown-menu/dropdown-menu"
import { Select } from "@/components/arc/select/select"
import { href, navigate } from "@/features/shell/route"
import type { Guru } from "./model"
import styles from "./gurus.module.css"

export interface Copying {
  title: string
  tone: BadgeTone
  /** Why it is not plainly copying, when it is not. */
  detail: string | null
}

/** The guru's name with whether they are being copied, the account the figures are for, and the page's actions. */
export function GuruHeader({
  guru,
  accountId,
  onAccountChange,
  copying,
  live,
  onRefresh,
}: {
  guru: Guru
  /** The account the figures and the chart are for. */
  accountId: string
  onAccountChange: (id: string) => void
  copying: Copying | null
  live: boolean
  onRefresh: () => void
}) {
  return (
    <header className={styles.header}>
      <Breadcrumb items={[{ label: "Gurus", href: href("gurus") }, { label: guru.name }]} />
      <div className={styles.identity}>
        <div className={styles.title}>
          <div className={styles.titleRow}>
            <h1>{guru.name}</h1>
            {copying && <Badge tone={copying.tone}>{copying.title}</Badge>}
            {live && <Badge tone="warning">Live</Badge>}
          </div>
          {guru.accounts.length > 0 && (
            <p className={styles.copied}>
              Copied into <strong>{guru.accounts.map((a) => a.id).join(", ")}</strong>
              {copying?.detail ? `. ${copying.detail}` : ""}
            </p>
          )}
        </div>
        <div className={styles.actions}>
          {guru.accounts.length > 1 && <Select className={styles.account} label="Account" value={accountId} onValueChange={onAccountChange} options={guru.accounts.map((a) => ({ value: a.id, label: a.id }))} />}
          <DropdownMenu
            label="More actions"
            items={[
              { label: "Refresh", icon: <RefreshIcon width={16} height={16} aria-hidden="true" />, onSelect: onRefresh },
              { label: "View in Activity", icon: <Activity01Icon width={16} height={16} aria-hidden="true" />, onSelect: () => navigate("activity") },
              { label: "Open Connections", icon: <Link01Icon width={16} height={16} aria-hidden="true" />, onSelect: () => navigate("settings", "connections") },
            ]}
          />
        </div>
      </div>
    </header>
  )
}
