import { useState } from "react"
import { HistoryIcon } from "@/components/icons/HistoryIcon"
import type { AccountOverview, AccountOverviewPage } from "../../../shared/contract"
import { Button } from "@/components/arc/button/button"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { navigate } from "@/features/shell/route"
import { type Loaded, useResult } from "@/lib/use-result"
import { earlierAccounts, recordSummary } from "./records"
import { SectionError } from "./SectionError"
import { SettingsRow } from "./SettingsRow"
import { SectionSkeleton, SettingsSection } from "./SettingsSection"

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
      <Button type="button" variant="secondary" size="sm" onClick={() => navigate("accounts", account.account_id)} aria-label={`Open the record of ${account.account_id}`}>
        Open
      </Button>
      <Button type="button" variant="danger" size="sm" disabled={working} onClick={remove} aria-label={`Delete the record of ${account.account_id}`}>
        Delete
      </Button>
    </SettingsRow>
  )
}

/**
 * Records of accounts the setup no longer has, so they never wait unseen for a name to be used again.
 * Each can be opened or deleted; nothing is deleted on its own.
 */
export function OldRecordsPage({ accounts }: { accounts: Loaded<AccountOverviewPage> & { retry: () => void } }) {
  const setup = useResult(() => window.copytrading.read.getSetup(), "setup")
  if (accounts.status === "loading" || setup.status === "loading") return <SectionSkeleton label="Loading old records" />
  if (accounts.status === "error") return <SectionError title="Account records did not load" message={accounts.error} onRetry={accounts.retry} />
  if (setup.status === "error") return <SectionError title="The saved setup did not load" message={setup.error} onRetry={setup.retry} />
  const old = earlierAccounts(accounts.data.items, setup.data?.configuration.accounts.map((a) => a.id) ?? [])
  if (old.length === 0) {
    return <EmptyState title="No old records" description="Every record belongs to an account in your setup." icon={<HistoryIcon width={24} height={24} aria-hidden="true" />} />
  }
  return (
    <SettingsSection>
      {old.map((account) => (
        <Row key={account.account_id} account={account} onDeleted={accounts.retry} />
      ))}
    </SettingsSection>
  )
}
