import { LandmarkIcon } from "lucide-react"
import type { AccountOverviewPage, EngineState } from "../../../shared/contract"
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuBadge,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarMenuSkeleton,
  SidebarSeparator,
} from "@/components/ui/sidebar"
import { AssistantPanel } from "@/features/assistant/AssistantPanel"
import { money } from "@/lib/format"
import { type Loaded } from "@/lib/use-result"
import { CopyingStatus } from "./CopyingStatus"
import { type Route, type ScreenId, href } from "./route"
import { SCREENS } from "./screens"

interface Props {
  route: Route
  accounts: Loaded<AccountOverviewPage>
  selectedAccountId: string | null
  engine: EngineState
}

function AccountList({ accounts, selectedAccountId }: Pick<Props, "accounts" | "selectedAccountId">) {
  if (accounts.status === "loading") {
    return (
      <SidebarMenu aria-label="Loading accounts">
        <SidebarMenuSkeleton showIcon />
        <SidebarMenuSkeleton showIcon />
      </SidebarMenu>
    )
  }
  if (accounts.status === "error") return <p className="text-muted-foreground px-2 text-xs">Accounts are unavailable.</p>
  if (accounts.data.items.length === 0) return <p className="text-muted-foreground px-2 text-xs">No accounts yet.</p>
  return (
    <SidebarMenu>
      {accounts.data.items.map((account) => (
        <SidebarMenuItem key={account.account_id}>
          <SidebarMenuButton isActive={account.account_id === selectedAccountId} render={<a href={href("accounts", account.account_id)} />}>
            <LandmarkIcon aria-hidden="true" />
            <span>{account.account_id}</span>
          </SidebarMenuButton>
          {account.balance && <SidebarMenuBadge className="tabular-nums">{money(account.balance.equity).replace(/\.\d+$/, "")}</SidebarMenuBadge>}
        </SidebarMenuItem>
      ))}
    </SidebarMenu>
  )
}

function NavItem({ screen, route }: { screen: ScreenId; route: Route }) {
  const { title, icon: Icon } = SCREENS[screen]
  return (
    <SidebarMenuItem>
      <SidebarMenuButton isActive={route.screen === screen} render={<a href={href(screen)} />}>
        <Icon aria-hidden="true" />
        <span>{title}</span>
      </SidebarMenuButton>
    </SidebarMenuItem>
  )
}

export function AppSidebar({ route, accounts, selectedAccountId, engine }: Props) {
  return (
    <Sidebar variant="inset">
      <SidebarHeader>
        <div className="px-2 py-1.5 text-sm font-semibold tracking-tight">CopyTrading</div>
      </SidebarHeader>
      <SidebarContent role="navigation" aria-label="Main">
        <SidebarGroup>
          <SidebarGroupLabel>Accounts</SidebarGroupLabel>
          <SidebarGroupContent>
            <AccountList accounts={accounts} selectedAccountId={selectedAccountId} />
          </SidebarGroupContent>
        </SidebarGroup>
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu>
              <NavItem screen="gurus" route={route} />
              <NavItem screen="activity" route={route} />
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>
      <SidebarFooter>
        <SidebarSeparator className="mx-0" />
        <SidebarMenu>
          <AssistantPanel />
          <NavItem screen="getting-started" route={route} />
          <NavItem screen="connections" route={route} />
          <NavItem screen="settings" route={route} />
          <CopyingStatus engine={engine} />
        </SidebarMenu>
      </SidebarFooter>
    </Sidebar>
  )
}
