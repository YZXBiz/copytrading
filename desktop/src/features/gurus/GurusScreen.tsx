import { ChevronRightIcon, UsersIcon } from "lucide-react"
import type { AccountOverviewPage } from "../../../shared/contract"
import { RegionError } from "@/components/region-error"
import { Frame, FramePanel } from "@/components/reui/frame"
import { EmptyState } from "@/components/empty-state"
import { navigate } from "@/features/shell/route"
import { Item, ItemActions, ItemContent, ItemGroup, ItemSeparator, ItemTitle } from "@/components/ui/item"
import { Skeleton } from "@/components/ui/skeleton"
import { href } from "@/features/shell/route"
import { type Loaded } from "@/lib/use-result"
import { Fragment } from "react"
import { GuruDestinations } from "./GuruDestinations"
import { GuruPage } from "./GuruPage"
import { useGurus } from "./use-gurus"

/** The gurus the saved setup copies; one of them opens as their page. */
export function GurusScreen({ guruId, accounts }: { guruId: string | null; accounts: Loaded<AccountOverviewPage> }) {
  const { gurus, config, setup } = useGurus()
  // With one guru there is nothing to choose between: Gurus opens their page.
  const guru = guruId ? gurus.find((g) => g.id === guruId) : gurus.length === 1 ? gurus[0] : undefined
  if (guru) return <GuruPage guru={guru} accounts={accounts} setUpAccountIds={new Set(config?.accounts.map((a) => a.id))} />

  return (
    <Frame spacing="sm">
      <FramePanel className="p-0">
        {setup.status === "loading" && (
          <div role="status" aria-label="Loading gurus" className="flex flex-col gap-4 p-3">
            {Array.from({ length: 3 }, (_, i) => (
              <div key={i} className="flex flex-col gap-1.5">
                <Skeleton className="h-4 w-1/4" />
                <Skeleton className="h-3 w-1/2" />
              </div>
            ))}
          </div>
        )}
        {setup.status === "error" && (
          <div className="p-3">
            <RegionError title="Gurus did not load" message={setup.error} onRetry={setup.retry} />
          </div>
        )}
        {setup.status === "ready" && gurus.length === 0 && (
          <EmptyState
            icon={UsersIcon}
            title={guruId ? "This guru is not in your setup" : "No gurus yet"}
            description="Gurus you copy appear here once they are set up in Connections."
            action={{ label: "Open Connections", onClick: () => navigate("settings", "connections") }}
          />
        )}
        {setup.status === "ready" && gurus.length > 0 && (
          <ItemGroup className="gap-0 p-1">
            {gurus.map((g, index) => (
              <Fragment key={g.id}>
                {index > 0 && <ItemSeparator className="my-0" />}
                <Item render={<a href={href("gurus", g.id)} />}>
                  <ItemContent>
                    <ItemTitle>{g.name}</ItemTitle>
                  </ItemContent>
                  <ItemActions>
                    <GuruDestinations guru={g} />
                    <ChevronRightIcon aria-hidden className="text-muted-foreground size-4" />
                  </ItemActions>
                </Item>
              </Fragment>
            ))}
          </ItemGroup>
        )}
      </FramePanel>
    </Frame>
  )
}
