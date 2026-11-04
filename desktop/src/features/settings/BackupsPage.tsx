import type { AccountOverviewPage } from "../../../shared/contract"
import { RegionError } from "@/components/region-error"
import { SectionSkeleton } from "./SettingsSection"
import { type Loaded, useResult } from "@/lib/use-result"
import { BackupRestore } from "./BackupRestore"
import { EarlierAccounts } from "./EarlierAccounts"

/** The records of accounts the setup no longer has, and backing up or restoring the records. */
export function BackupsPage({ accounts }: { accounts: Loaded<AccountOverviewPage> & { retry: () => void } }) {
  const setup = useResult(() => window.copytrading.read.getSetup(), "setup")
  const pending = useResult(() => window.copytrading.read.getRestoreCandidate(), "restore-candidate")
  return (
    <div className="flex flex-col gap-5">
      {setup.status === "loading" ? (
        <SectionSkeleton />
      ) : setup.status === "error" ? (
        <RegionError title="The saved setup did not load" message={setup.error} onRetry={setup.retry} />
      ) : (
        <EarlierAccounts accounts={accounts} saved={setup.data?.configuration.accounts.map((a) => a.id) ?? []} onRefresh={accounts.retry} />
      )}
      {pending.status === "error" ? (
        <RegionError title="Restore status did not load" message={pending.error} onRetry={pending.retry} />
      ) : (
        // Stays mounted while the status reloads, so a note and a previewed backup are not lost.
        <BackupRestore pending={pending.status === "ready" ? pending.data : null} checking={pending.status === "loading"} onChanged={pending.retry} />
      )}
    </div>
  )
}
