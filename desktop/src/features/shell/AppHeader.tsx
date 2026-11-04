import { Breadcrumb, BreadcrumbItem, BreadcrumbLink, BreadcrumbList, BreadcrumbPage, BreadcrumbSeparator } from "@/components/ui/breadcrumb"
import { AssistantToggle } from "@/features/assistant/AssistantToggle"
import { href } from "./route"
import { SCREENS } from "./screens"
import type { Route } from "./route"

/** app-shell-2's header: the breadcrumb on the left, with the Assistant's one control on the right. */
export function AppHeader({ route, selectedAccountId }: { route: Route; selectedAccountId: string | null }) {
  const screen = SCREENS[route.screen]
  return (
    <header className="flex h-12 shrink-0 items-center gap-2 pt-2 transition-[width,height] ease-linear group-has-data-[collapsible=icon]/sidebar-wrapper:h-12">
      <div className="flex min-w-0 items-center gap-2 pr-4 pl-2">
        <Breadcrumb className="min-w-0">
          <BreadcrumbList className="flex-nowrap">
            {selectedAccountId && (
              <>
                <BreadcrumbItem>
                  <BreadcrumbLink href={href("accounts")}>{screen.title}</BreadcrumbLink>
                </BreadcrumbItem>
                <BreadcrumbSeparator />
              </>
            )}
            <BreadcrumbItem className="min-w-0">
              <BreadcrumbPage className="truncate">{selectedAccountId ?? screen.title}</BreadcrumbPage>
            </BreadcrumbItem>
          </BreadcrumbList>
        </Breadcrumb>
      </div>
      <div className="ms-auto shrink-0 pr-4">
        <AssistantToggle />
      </div>
    </header>
  )
}
