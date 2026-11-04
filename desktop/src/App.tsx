import { Breadcrumb, BreadcrumbItem, BreadcrumbList, BreadcrumbPage, BreadcrumbSeparator } from "@/components/ui/breadcrumb"
import { SidebarInset, SidebarProvider, SidebarTrigger } from "@/components/ui/sidebar"
import { TooltipProvider } from "@/components/ui/tooltip"
import { AppSidebar } from "@/features/shell/AppSidebar"
import { useEngineState } from "@/features/shell/engine-state"
import { useRoute } from "@/features/shell/route"
import { SCREENS } from "@/features/shell/screens"
import { useResult } from "@/lib/use-result"

export default function App() {
  const route = useRoute()
  const engine = useEngineState()
  // Reads again when the engine finishes starting: until then every read answers that it is not ready.
  const accounts = useResult(() => window.copytrading.read.getAccounts(), `accounts:${engine.state}`)
  const screen = SCREENS[route.screen]
  const selectedAccountId = route.screen === "accounts" ? (route.id ?? (accounts.status === "ready" ? accounts.data.items[0]?.account_id : null) ?? null) : null

  return (
    <TooltipProvider>
      <SidebarProvider>
        <AppSidebar route={route} accounts={accounts} selectedAccountId={selectedAccountId} engine={engine} />
        <SidebarInset className="min-w-0 overflow-hidden">
          <header className="flex h-12 shrink-0 items-center gap-2 border-b px-4">
            <SidebarTrigger className="-ml-1" />
            <Breadcrumb className="min-w-0">
              <BreadcrumbList className="flex-nowrap">
                {selectedAccountId && (
                  <>
                    <BreadcrumbItem>{screen.title}</BreadcrumbItem>
                    <BreadcrumbSeparator />
                  </>
                )}
                <BreadcrumbItem className="min-w-0">
                  <BreadcrumbPage className="truncate">{selectedAccountId ?? screen.title}</BreadcrumbPage>
                </BreadcrumbItem>
              </BreadcrumbList>
            </Breadcrumb>
          </header>
          <main className="flex-1 overflow-auto p-6">{screen.render({ route, accounts })}</main>
        </SidebarInset>
      </SidebarProvider>
    </TooltipProvider>
  )
}
