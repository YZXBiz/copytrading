import { ActivityIcon, EllipsisIcon, LinkIcon, RefreshCwIcon, ShieldCheckIcon } from "lucide-react"
import { Breadcrumb, BreadcrumbItem, BreadcrumbLink, BreadcrumbList, BreadcrumbPage, BreadcrumbSeparator } from "@/components/ui/breadcrumb"
import { Button } from "@/components/ui/button"
import { DropdownMenu, DropdownMenuContent, DropdownMenuGroup, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import { href, navigate } from "@/features/shell/route"

/** dashboard-8's navbar: Accounts > the account on the left, the account's actions on the right (Stop or Start Copying sits in the band). */
export function AccountNavbar({
  accountId,
  canEditLimits,
  onEditLimits,
  onRefresh,
  onOpenConnections,
}: {
  accountId: string
  canEditLimits: boolean
  onEditLimits: () => void
  onRefresh: () => void
  onOpenConnections: () => void
}) {
  return (
    <header className="flex min-h-9 w-full shrink-0 flex-col gap-2 pb-1 sm:flex-row sm:items-center sm:justify-between" aria-label="Account command header">
      <Breadcrumb className="min-w-0">
        <BreadcrumbList className="flex-nowrap">
          <BreadcrumbItem>
            <BreadcrumbLink href={href("accounts")}>Accounts</BreadcrumbLink>
          </BreadcrumbItem>
          <BreadcrumbSeparator />
          <BreadcrumbItem className="min-w-0">
            <BreadcrumbPage className="truncate">{accountId}</BreadcrumbPage>
          </BreadcrumbItem>
        </BreadcrumbList>
      </Breadcrumb>
      <div className="flex shrink-0 items-center gap-2">
        <DropdownMenu>
          <DropdownMenuTrigger render={<Button type="button" variant="outline" size="icon-sm" aria-label="Account actions" />}>
            <EllipsisIcon aria-hidden="true" />
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-48">
            <DropdownMenuGroup>
              <DropdownMenuItem disabled={!canEditLimits} onClick={onEditLimits}>
                <ShieldCheckIcon aria-hidden="true" />
                Edit Limits
              </DropdownMenuItem>
              <DropdownMenuItem onClick={onRefresh}>
                <RefreshCwIcon aria-hidden="true" />
                Refresh
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => navigate("activity")}>
                <ActivityIcon aria-hidden="true" />
                View in Activity
              </DropdownMenuItem>
              <DropdownMenuItem onClick={onOpenConnections}>
                <LinkIcon aria-hidden="true" />
                Open Connections
              </DropdownMenuItem>
            </DropdownMenuGroup>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  )
}
