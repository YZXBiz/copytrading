import type { ReactNode } from "react"
import { LandmarkIcon } from "lucide-react"
import type { AccountOverview, AccountOverviewPage } from "../../../shared/contract"
import { Button } from "@/components/ui/button"
import {
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuBadge,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarMenuSkeleton,
} from "@/components/ui/sidebar"
import { RollingNumber } from "@/components/rolling-number"
import { USD_WHOLE_OPTIONS } from "@/features/account/balance-panel/format"
import { type Loaded } from "@/lib/use-result"
import { type Route, type ScreenId, href } from "./route"
import { SCREENS } from "./screens"

function Accounts({
  accounts,
  live,
  selectedAccountId,
}: {
  accounts: Loaded<AccountOverviewPage> & { retry: () => void }
  live: AccountOverview[]
  selectedAccountId: string | null
}): ReactNode {
  if (accounts.status === "loading") {
    return (
      <SidebarMenu aria-label="Loading accounts" role="status">
        <SidebarMenuSkeleton showIcon />
        <SidebarMenuSkeleton showIcon />
      </SidebarMenu>
    )
  }
  if (accounts.status === "error") {
    return (
      <div className="text-muted-foreground flex items-center gap-1 px-2 text-xs in-data-[state=collapsed]:hidden" title={accounts.error}>
        <span className="min-w-0 truncate">Accounts did not load.</span>
        <Button type="button" variant="link" size="xs" onClick={accounts.retry}>
          Retry
        </Button>
      </div>
    )
  }
  if (live.length === 0) return <p className="text-muted-foreground px-2 text-xs in-data-[state=collapsed]:hidden">No accounts yet.</p>
  return (
    <SidebarMenu>
      {live.map((account) => (
        <SidebarMenuItem key={account.account_id}>
          <SidebarMenuButton tooltip={account.account_id} isActive={account.account_id === selectedAccountId} render={<a href={href("accounts", account.account_id)} />}>
            <LandmarkIcon aria-hidden="true" />
            <span>{account.account_id}</span>
            {account.balance && (
              <SidebarMenuBadge className="tabular-nums">
                <RollingNumber value={Number(account.balance.equity)} format={USD_WHOLE_OPTIONS} />
              </SidebarMenuBadge>
            )}
          </SidebarMenuButton>
        </SidebarMenuItem>
      ))}
    </SidebarMenu>
  )
}

function LeafNavItem({ screen, route }: { screen: ScreenId; route: Route }) {
  const { title, icon: Icon } = SCREENS[screen]
  return (
    <SidebarMenuItem>
      <SidebarMenuButton tooltip={title} isActive={route.screen === screen} render={<a href={href(screen)} />}>
        <Icon aria-hidden="true" />
        <span>{title}</span>
      </SidebarMenuButton>
    </SidebarMenuItem>
  )
}

interface Props {
  route: Route
  accounts: Loaded<AccountOverviewPage> & { retry: () => void }
  live: AccountOverview[]
  selectedAccountId: string | null
}

/** The live accounts, then Gurus and Activity: what is used daily. */
export function NavMain({ route, accounts, live, selectedAccountId }: Props) {
  return (
    <>
      <SidebarGroup>
        <SidebarGroupLabel className="in-data-[state=collapsed]:hidden">Accounts</SidebarGroupLabel>
        <SidebarGroupContent>
          <Accounts accounts={accounts} live={live} selectedAccountId={selectedAccountId} />
        </SidebarGroupContent>
      </SidebarGroup>
      <SidebarGroup>
        <SidebarGroupContent>
          <SidebarMenu>
            <LeafNavItem screen="gurus" route={route} />
            <LeafNavItem screen="activity" route={route} />
          </SidebarMenu>
        </SidebarGroupContent>
      </SidebarGroup>
    </>
  )
}
