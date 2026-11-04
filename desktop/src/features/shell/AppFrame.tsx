import { type ReactNode, useCallback } from "react"
import type { AccountOverview, AccountOverviewPage, EngineState, TradingConfiguration } from "../../../shared/contract"
import { SidebarInset, SidebarProvider, useSidebar } from "@/components/ui/sidebar"
import { AssistantFrame } from "@/features/assistant/AssistantFrame"
import { type Loaded } from "@/lib/use-result"
import { cn } from "@/lib/utils"
import { AppHeader } from "./AppHeader"
import { AppSidebar } from "./AppSidebar"
import type { Route } from "./route"

interface Props {
  route: Route
  accounts: Loaded<AccountOverviewPage> & { retry: () => void }
  live: AccountOverview[]
  old: AccountOverview[]
  setup: TradingConfiguration | null | undefined
  selectedAccountId: string | null
  engine: EngineState
  children: ReactNode
}

/** Below this width the floating sidebar folds to icons when the Assistant opens, so the page keeps its room. */
const ROOMY = 1280

function Frame({ children, ...props }: Props) {
  const { setOpen } = useSidebar()
  const makeRoom = useCallback(() => {
    if (window.innerWidth < ROOMY) setOpen(false)
  }, [setOpen])

  return (
    <>
      <AppSidebar {...props} />
      <SidebarInset className="min-w-0 overflow-hidden">
        <AssistantFrame onOpen={makeRoom}>
          <AppHeader route={props.route} selectedAccountId={props.selectedAccountId} />
          <main className="min-h-0 flex-1 overflow-auto py-2 pr-4 pl-2">{children}</main>
        </AssistantFrame>
      </SidebarInset>
    </>
  )
}

/** app-shell-2: a floating sidebar that collapses to icons beside the page, whose provider carries the block's own sidebar classes. */
export function AppFrame(props: Props) {
  return (
    <SidebarProvider
      className={cn(
        "h-svh [--sidebar-width:260px]",
        "[--sidebar-border:transparent]",
        "[&_[data-slot=sidebar-inner]]:border-border/80 [&_[data-slot=sidebar-inner]]:border",
        "[&_[data-slot=sidebar-inner]]:shadow-xs [&_[data-slot=sidebar-inner]]:shadow-black/5",
        "[&_[data-slot=sidebar-menu-button][data-active]]:border-border/60! [&_[data-slot=sidebar-menu-button][data-active]]:border",
        "[&_[data-slot=sidebar-menu-button][data-active]]:shadow-xs! [&_[data-slot=sidebar-menu-button][data-active]]:shadow-black/5!",
        "[&_[data-slot=sidebar-menu-button][data-active]]:bg-background! [&_[data-slot=sidebar-menu-button][data-active]]:hover:bg-background! **:data-[slot=sidebar-menu-button]:hover:bg-transparent!",
        "[&_[data-slot=sidebar-menu-button][data-active]]:text-foreground [&_[data-slot=sidebar-menu-button][data-active]>svg]:text-primary [&_[data-slot=sidebar-menu-button][data-active]>svg]:opacity-100",
        "**:data-[slot=sidebar-menu-button]:text-accent-foreground/80 **:data-[slot=sidebar-menu-button]:hover:text-foreground",
        "[&_[data-collapsible=icon]_[data-slot=sidebar-menu-button][data-active]>svg]:-ml-px",
        "[&_[data-slot=sidebar-menu-button]:hover>svg]:opacity-100 [&_[data-slot=sidebar-menu-button]>svg]:opacity-60",
        "[&_[data-slot=sidebar-menu-sub-button][data-active]]:border-border/60! [&_[data-slot=sidebar-menu-sub-button][data-active]]:border",
        "[&_[data-slot=sidebar-menu-sub-button][data-active]]:shadow-xs! [&_[data-slot=sidebar-menu-sub-button][data-active]]:shadow-black/5!",
        "[&_[data-slot=sidebar-menu-sub-button][data-active]]:bg-background! [&_[data-slot=sidebar-menu-sub-button][data-active]]:hover:bg-background! **:data-[slot=sidebar-menu-sub-button]:hover:bg-transparent!",
        "[&_[data-slot=sidebar-menu-sub-button][data-active]]:text-foreground [&_[data-slot=sidebar-menu-sub-button][data-active]>svg]:text-primary [&_[data-slot=sidebar-menu-sub-button][data-active]>svg]:opacity-100",
        "**:data-[slot=sidebar-menu-sub-button]:text-accent-foreground/80 **:data-[slot=sidebar-menu-sub-button]:hover:text-foreground",
        "[&_[data-slot=sidebar-menu-sub-button]:hover>svg]:opacity-100 [&_[data-slot=sidebar-menu-sub-button]>svg]:opacity-60",
      )}
    >
      <Frame {...props} />
    </SidebarProvider>
  )
}
