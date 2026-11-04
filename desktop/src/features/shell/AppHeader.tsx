import { PanelLeftIcon } from "lucide-react"
import { Breadcrumb, BreadcrumbItem, BreadcrumbList, BreadcrumbPage } from "@/components/ui/breadcrumb"
import { Button } from "@/components/ui/button"
import { AssistantToggle } from "@/features/assistant/AssistantToggle"
import { SCREENS } from "./screens"
import type { Route } from "./route"

/** app-shell-2's header: the screen's breadcrumb on the left, with the Assistant's one control on the right. */
export function AppHeader({ route, selectedAccountId, onToggleNav }: { route: Route; selectedAccountId: string | null; onToggleNav: () => void }) {
  const screen = SCREENS[route.screen]
  return (
    <header className="drag-region flex h-12 shrink-0 items-center gap-2 pt-2 transition-[width,height] ease-linear group-has-data-[collapsible=icon]/sidebar-wrapper:h-12">
      <div className="flex min-w-0 items-center gap-2 pr-4 pl-2 group-has-data-[collapsible=icon]/sidebar-wrapper:pl-4">
        {/* Below md the sidebar is a sheet and this is its only way in. It drives the sidebar's own provider, not the Assistant's. */}
        <Button type="button" variant="ghost" size="icon-sm" aria-label="Show navigation" onClick={onToggleNav} className="-ml-1 opacity-60 hover:opacity-100 md:hidden">
          <PanelLeftIcon aria-hidden="true" />
        </Button>
        {/* An account page carries its own breadcrumb row beside its actions. */}
        {!selectedAccountId && (
          <Breadcrumb className="min-w-0">
            <BreadcrumbList className="flex-nowrap">
              <BreadcrumbItem className="min-w-0">
                <BreadcrumbPage className="truncate">{screen.title}</BreadcrumbPage>
              </BreadcrumbItem>
            </BreadcrumbList>
          </Breadcrumb>
        )}
      </div>
      <div className="ms-auto shrink-0 pr-4">
        <AssistantToggle />
      </div>
    </header>
  )
}
