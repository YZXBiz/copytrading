import { useState, type ReactNode } from "react"
import { ArchiveIcon, ChevronRightIcon, LandmarkIcon } from "lucide-react"
import type { AccountOverview, AccountOverviewPage } from "../../../shared/contract"
import { Button } from "@/components/ui/button"
import { DropdownMenu, DropdownMenuContent, DropdownMenuGroup, DropdownMenuItem, DropdownMenuLabel, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import {
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuBadge,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarMenuSkeleton,
  SidebarMenuSub,
  SidebarMenuSubButton,
  SidebarMenuSubItem,
  useSidebar,
} from "@/components/ui/sidebar"
import { RollingNumber } from "@/components/rolling-number"
import { USD_WHOLE_OPTIONS } from "@/features/account/balance-panel/format"
import { cn } from "@/lib/utils"
import { type Loaded } from "@/lib/use-result"
import { type Route, type ScreenId, href } from "./route"
import { SCREENS } from "./screens"

// app-shell-2's nav: a labelled group of leaf items and one collapsible item. The collapsible holds the old records; in the
// icon rail its children open in a side menu instead of pushing the next item down.

function OldRecords({ records, selectedAccountId }: { records: AccountOverview[]; selectedAccountId: string | null }) {
  const { state } = useSidebar()
  const hasActive = records.some((a) => a.account_id === selectedAccountId)
  // Kept on the always-mounted parent so the open state survives a collapse and expand of the rail.
  const [open, setOpen] = useState(hasActive)

  if (state === "collapsed") {
    return (
      <SidebarMenuItem>
        <DropdownMenu>
          <DropdownMenuTrigger render={<SidebarMenuButton tooltip="Old records" isActive={hasActive} aria-label="Old records" />}>
            <ArchiveIcon aria-hidden="true" />
            <span>Old records</span>
          </DropdownMenuTrigger>
          <DropdownMenuContent side="right" align="start" sideOffset={8} className="min-w-48">
            <DropdownMenuGroup>
              <DropdownMenuLabel>Old records</DropdownMenuLabel>
              {records.map((a) => (
                <DropdownMenuItem key={a.account_id} render={<a href={href("accounts", a.account_id)} />}>
                  {a.account_id}
                </DropdownMenuItem>
              ))}
            </DropdownMenuGroup>
          </DropdownMenuContent>
        </DropdownMenu>
      </SidebarMenuItem>
    )
  }

  return (
    <SidebarMenuItem>
      <SidebarMenuButton tooltip="Old records" isActive={hasActive && !open} onClick={() => setOpen((was) => !was)} aria-expanded={open} aria-controls="subnav-old-records">
        <ArchiveIcon aria-hidden="true" />
        <span>Old records</span>
        <ChevronRightIcon className={cn("ml-auto size-4 shrink-0 opacity-60 transition-transform duration-200", open && "rotate-90")} aria-hidden="true" />
      </SidebarMenuButton>
      {open && (
        <SidebarMenuSub id="subnav-old-records">
          {records.map((a) => (
            <SidebarMenuSubItem key={a.account_id}>
              <SidebarMenuSubButton render={<a href={href("accounts", a.account_id)} />} isActive={a.account_id === selectedAccountId}>
                <span>{a.account_id}</span>
              </SidebarMenuSubButton>
            </SidebarMenuSubItem>
          ))}
        </SidebarMenuSub>
      )}
    </SidebarMenuItem>
  )
}

function Accounts({
  accounts,
  live,
  old,
  selectedAccountId,
}: {
  accounts: Loaded<AccountOverviewPage> & { retry: () => void }
  live: AccountOverview[]
  old: AccountOverview[]
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
  if (live.length + old.length === 0) return <p className="text-muted-foreground px-2 text-xs in-data-[state=collapsed]:hidden">No accounts yet.</p>
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
      {old.length > 0 && <OldRecords records={old} selectedAccountId={selectedAccountId} />}
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
  old: AccountOverview[]
  selectedAccountId: string | null
}

export function NavMain({ route, accounts, live, old, selectedAccountId }: Props) {
  return (
    <>
      <SidebarGroup>
        <SidebarGroupLabel className="in-data-[state=collapsed]:hidden">Accounts</SidebarGroupLabel>
        <SidebarGroupContent>
          <Accounts accounts={accounts} live={live} old={old} selectedAccountId={selectedAccountId} />
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
