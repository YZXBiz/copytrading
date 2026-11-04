import type { AccountOverview, AccountOverviewPage, EngineState, TradingConfiguration } from "../../../shared/contract"
import { Separator } from "@/components/ui/separator"
import { Sidebar, SidebarContent, SidebarFooter, SidebarHeader, SidebarMenu, SidebarTrigger } from "@/components/ui/sidebar"
import { type Loaded } from "@/lib/use-result"
import { CopyingStatus } from "./CopyingStatus"
import { Logo } from "./Logo"
import { NavMain } from "./NavMain"
import { NavSecondary } from "./NavSecondary"
import { type Route } from "./route"
import { SearchForm } from "./SearchForm"

interface Props {
  route: Route
  accounts: Loaded<AccountOverviewPage> & { retry: () => void }
  live: AccountOverview[]
  old: AccountOverview[]
  setup: TradingConfiguration | null | undefined
  selectedAccountId: string | null
  engine: EngineState
}

/** app-shell-2: a floating sidebar that collapses to icons, with search above the nav and the copying status in its footer. */
export function AppSidebar({ route, accounts, live, old, setup, selectedAccountId, engine }: Props) {
  return (
    <Sidebar collapsible="icon" variant="floating">
      {/* The traffic lights sit here, inset in the sidebar (hiddenInset); the strip drags the window. */}
      <div className="drag-region h-6 shrink-0" aria-hidden="true" />
      <SidebarHeader className="flex flex-row items-center justify-between in-data-[state=collapsed]:flex-col in-data-[state=collapsed]:items-start in-data-[state=collapsed]:justify-center">
        <div className="inline-flex min-h-10 items-center gap-2 px-0.5 transition-all duration-200 ease-linear">
          <Logo />
          <span className="text-sm font-medium in-data-[state=collapsed]:hidden">CopyTrading</span>
        </div>
        <SidebarTrigger className="opacity-60 hover:opacity-100 [&_svg]:transition-transform [&_svg]:duration-200 in-data-[state=collapsed]:[&_svg]:rotate-180" />
      </SidebarHeader>

      <SidebarContent role="navigation" aria-label="Main">
        <div className="py-2 pt-2">
          <SearchForm live={live} old={old} setup={setup} />
        </div>
        <NavMain route={route} accounts={accounts} live={live} old={old} selectedAccountId={selectedAccountId} />
        <div className="mt-auto">
          <NavSecondary route={route} />
        </div>
      </SidebarContent>

      <SidebarFooter>
        <div className="px-1">
          <Separator />
        </div>
        <SidebarMenu>
          <CopyingStatus engine={engine} />
        </SidebarMenu>
      </SidebarFooter>
    </Sidebar>
  )
}
