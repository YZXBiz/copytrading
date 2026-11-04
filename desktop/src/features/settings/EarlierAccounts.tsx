import { useState } from "react"
import type { AccountOverview } from "../../../shared/contract"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Skeleton } from "@/components/ui/skeleton"
import type { Loaded } from "@/lib/use-result"
import { earlierAccounts, recordSummary } from "./records"
import { SettingsRow } from "./SettingsRow"
import { SettingsSection } from "./SettingsSection"

function Row({ account, onDeleted }: { account: AccountOverview; onDeleted: () => void }) {
  const [working, setWorking] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  async function remove() {
    setWorking(true)
    setProblem(null)
    // Main asks the owner first; a Cancel there comes back as `cancelled` and shows nothing.
    const result = await window.copytrading.act.deleteAccountRecord({ account_id: account.account_id })
    setWorking(false)
    if (result.ok) onDeleted()
    else if (!result.cancelled) setProblem(result.error)
  }
  return (
    <SettingsRow
      title={account.account_id}
      description={problem ? `${recordSummary(account)}\n${problem}` : recordSummary(account)}
      tone={problem ? "caution" : undefined}
    >
      <Button type="button" variant="destructive" size="sm" disabled={working} onClick={remove} aria-label={`Delete the record of ${account.account_id}`}>
        Delete…
      </Button>
    </SettingsRow>
  )
}

/**
 * Records of accounts the setup no longer has, so they never wait unseen for a name to be used again.
 * Each can be deleted; nothing is deleted on its own.
 */
export function EarlierAccounts({ accounts, saved, onRefresh }: { accounts: Loaded<{ items: AccountOverview[] }>; saved: string[]; onRefresh: () => void }) {
  if (accounts.status === "loading") return <Skeleton className="h-16 w-full" />
  if (accounts.status === "error") return <RegionError title="Account records did not load" message={accounts.error} onRetry={onRefresh} />
  const earlier = earlierAccounts(accounts.data.items, saved)
  return (
    <SettingsSection title="Earlier Accounts" hint="Records of accounts no longer in your setup. The same keys under any name pick theirs up again.">
      {earlier.map((account) => (
        <Row key={account.account_id} account={account} onDeleted={onRefresh} />
      ))}
    </SettingsSection>
  )
}
