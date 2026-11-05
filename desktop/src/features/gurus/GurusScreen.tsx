import { UserGroupIcon } from "@/components/icons/UserGroupIcon"
import type { AccountOverviewPage } from "../../../shared/contract"
import { Button } from "@/components/arc/button/button"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import { RegionAlert } from "@/features/activity/RegionAlert"
import { navigate } from "@/features/shell/route"
import { type Loaded } from "@/lib/use-result"
import { GuruLeaderboard } from "./GuruLeaderboard"
import { GuruPage } from "./GuruPage"
import { useGurus } from "./use-gurus"
import styles from "./gurus.module.css"

/** The gurus the saved setup copies; one of them opens as their page. */
export function GurusScreen({ guruId, accounts }: { guruId: string | null; accounts: Loaded<AccountOverviewPage> }) {
  const { gurus, config, setup } = useGurus()
  // With one guru there is nothing to choose between: Gurus opens their page.
  const guru = guruId ? gurus.find((g) => g.id === guruId) : gurus.length === 1 ? gurus[0] : undefined
  if (guru) return <GuruPage guru={guru} accounts={accounts} setUpAccountIds={new Set(config?.accounts.map((a) => a.id))} />

  if (setup.status === "ready" && gurus.length > 0) {
    return <GuruLeaderboard gurus={gurus} accounts={accounts} setUpAccountIds={new Set(config?.accounts.map((a) => a.id))} />
  }

  return (
    <div className={styles.page}>
      {setup.status === "loading" && (
        <div role="status" aria-busy="true" aria-label="Loading gurus">
          <Skeleton label="Loading gurus" lines={3} avatar />
        </div>
      )}
      {setup.status === "error" && <RegionAlert title="Gurus did not load" message={setup.error} onRetry={setup.retry} />}
      {setup.status === "ready" && gurus.length === 0 && (
        <EmptyState
          icon={<UserGroupIcon width={24} height={24} aria-hidden="true" />}
          title={guruId ? "This guru is not in your setup" : "No gurus yet"}
          description="Gurus you copy appear here once they are set up in Connections."
          action={
            <Button variant="secondary" size="sm" onClick={() => navigate("settings", "connections")}>
              Open Connections
            </Button>
          }
        />
      )}
    </div>
  )
}
