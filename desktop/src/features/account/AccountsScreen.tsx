import type { AccountOverviewPage } from "../../../shared/contract"
import { Button } from "@/components/arc/button/button"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { type Loaded } from "@/lib/use-result"
import styles from "./account.module.css"
import { AccountPage } from "./AccountPage"
import { AccountPageSkeleton } from "./AccountPageSkeleton"
import { RegionNote } from "./RegionNote"

/** The Accounts screen: loading, error, no accounts, or the selected account's page. */
export function AccountsScreen({
  accounts,
  selectedAccountId,
  onRefresh,
  onOpenConnections,
}: {
  accounts: Loaded<AccountOverviewPage>
  selectedAccountId: string | null
  onRefresh: () => void
  onOpenConnections: () => void
}) {
  if (accounts.status === "loading") return <AccountPageSkeleton />
  if (accounts.status === "error") {
    return (
      <div className={styles.page}>
        <RegionNote title="Accounts did not load" message={accounts.error} onRetry={onRefresh} />
      </div>
    )
  }
  const account = accounts.data.items.find((a) => a.account_id === selectedAccountId) ?? accounts.data.items[0]
  if (!account) {
    return (
      <div className={styles.page}>
        <EmptyState
          title="No accounts yet"
          description="Connect a broker account to begin."
          action={
            <Button type="button" onClick={onOpenConnections}>
              Open Connections
            </Button>
          }
        />
      </div>
    )
  }
  return <AccountPage key={account.account_id} account={account} accounts={accounts.data.items} onRefresh={onRefresh} onOpenConnections={onOpenConnections} />
}
