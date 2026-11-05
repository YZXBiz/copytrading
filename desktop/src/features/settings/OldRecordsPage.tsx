import { useState } from "react"
import { HistoryIcon } from "@/components/icons/HistoryIcon"
import type { AccountOverview, AccountOverviewPage } from "../../../shared/contract"
import { Frame, FramePanel } from "@/components/reui/frame"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Empty, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { href } from "@/features/shell/route"
import { type Loaded, useResult } from "@/lib/use-result"
import { earlierAccounts, recordSummary } from "./records"
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
      <Button variant="outline" size="sm" render={<a href={href("accounts", account.account_id)} />} aria-label={`Open the record of ${account.account_id}`}>
        Open
      </Button>
      <Button type="button" variant="destructive" size="sm" disabled={working} onClick={remove} aria-label={`Delete the record of ${account.account_id}`}>
        Delete…
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
  if (accounts.status === "loading" || setup.status === "loading") return <SectionSkeleton />
  if (accounts.status === "error") return <RegionError title="Account records did not load" message={accounts.error} onRetry={accounts.retry} />
  if (setup.status === "error") return <RegionError title="The saved setup did not load" message={setup.error} onRetry={setup.retry} />
  const old = earlierAccounts(accounts.data.items, setup.data?.configuration.accounts.map((a) => a.id) ?? [])
  if (old.length === 0) {
    return (
      <Frame>
        <FramePanel>
          <Empty className="py-6">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <HistoryIcon />
              </EmptyMedia>
              <EmptyTitle>No old records</EmptyTitle>
              <EmptyDescription>Every record belongs to an account in your setup.</EmptyDescription>
            </EmptyHeader>
          </Empty>
        </FramePanel>
      </Frame>
    )
  }
  return (
    <SettingsSection>
      {old.map((account) => (
        <Row key={account.account_id} account={account} onDeleted={accounts.retry} />
      ))}
    </SettingsSection>
  )
}
