import { BankIcon } from "@/components/icons/BankIcon"
import type { AccountOverviewPage } from "../../../shared/contract"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { type Loaded } from "@/lib/use-result"
import { AccountPage } from "./AccountPage"
import { AccountPageSkeleton } from "./AccountPageSkeleton"

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
    return <RegionError title="Accounts did not load" message={accounts.error} onRetry={onRefresh} />
  }
  const account = accounts.data.items.find((a) => a.account_id === selectedAccountId) ?? accounts.data.items[0]
  if (!account) {
    return (
      <Empty className="min-h-[60vh]">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <BankIcon />
          </EmptyMedia>
          <EmptyTitle>No accounts yet</EmptyTitle>
          <EmptyDescription>Connect a broker account to begin.</EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <Button type="button" size="sm" onClick={onOpenConnections}>
            Open Connections
          </Button>
        </EmptyContent>
      </Empty>
    )
  }
  return <AccountPage key={account.account_id} account={account} accounts={accounts.data.items} onRefresh={onRefresh} onOpenConnections={onOpenConnections} />
}
