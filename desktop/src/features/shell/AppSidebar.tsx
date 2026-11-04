import { LandmarkIcon, PlugIcon, SettingsIcon, UsersIcon } from "lucide-react"
import type { AccountOverviewPage } from "../../../shared/contract"
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
import { money } from "@/lib/format"
import { type Loaded } from "@/lib/use-result"
import { CopyingStatus } from "./CopyingStatus"

export type Screen = "accounts" | "gurus" | "connections" | "settings"

interface Props {
  screen: Screen
  onScreen: (screen: Screen) => void
  accounts: Loaded<AccountOverviewPage>
  selectedAccountId: string | null
  onSelectAccount: (accountId: string) => void
}

function AccountList({ accounts, screen, selectedAccountId, onSelectAccount }: Omit<Props, "onScreen">) {
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
          <SidebarMenuButton
            isActive={screen === "accounts" && account.account_id === selectedAccountId}
            onClick={() => onSelectAccount(account.account_id)}
          >
            <LandmarkIcon aria-hidden="true" />
            <span>{account.account_id}</span>
          </SidebarMenuButton>
          {account.balance && <SidebarMenuBadge className="tabular-nums">{money(account.balance.equity).replace(/\.\d+$/, "")}</SidebarMenuBadge>}
        </SidebarMenuItem>
      ))}
    </SidebarMenu>
  )
}

export function AppSidebar({ screen, onScreen, accounts, selectedAccountId, onSelectAccount }: Props) {
  return (
    <Sidebar variant="inset">
      <SidebarHeader>
        <div className="px-2 py-1.5 text-sm font-semibold tracking-tight">CopyTrading</div>
      </SidebarHeader>
      <SidebarContent role="navigation" aria-label="Main">
        <SidebarGroup>
          <SidebarGroupLabel>Accounts</SidebarGroupLabel>
          <SidebarGroupContent>
            <AccountList accounts={accounts} screen={screen} selectedAccountId={selectedAccountId} onSelectAccount={onSelectAccount} />
          </SidebarGroupContent>
        </SidebarGroup>
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu>
              <SidebarMenuItem>
                <SidebarMenuButton isActive={screen === "gurus"} onClick={() => onScreen("gurus")}>
                  <UsersIcon aria-hidden="true" />
                  <span>Gurus</span>
                </SidebarMenuButton>
              </SidebarMenuItem>
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>
      <SidebarFooter>
        <SidebarSeparator className="mx-0" />
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton isActive={screen === "connections"} onClick={() => onScreen("connections")}>
              <PlugIcon aria-hidden="true" />
              <span>Connections</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
          <SidebarMenuItem>
            <SidebarMenuButton isActive={screen === "settings"} onClick={() => onScreen("settings")}>
              <SettingsIcon aria-hidden="true" />
              <span>Settings</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
          <CopyingStatus />
        </SidebarMenu>
      </SidebarFooter>
    </Sidebar>
  )
}
