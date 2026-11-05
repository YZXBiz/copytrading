// solution-analytics-8's header (MetricHeader), as shipped: a breadcrumb over a title row with its badge, a meta line, and the
// range select and the more menu on the right. Changed from the block: the data, and only the controls with a real action stay.
import { ActivityIcon, EllipsisIcon, LinkIcon, RefreshCwIcon, UsersIcon } from "lucide-react"
import { Badge, type BadgeProps } from "@/components/reui/badge"
import { Breadcrumb, BreadcrumbItem, BreadcrumbLink, BreadcrumbList, BreadcrumbPage, BreadcrumbSeparator } from "@/components/ui/breadcrumb"
import { Button } from "@/components/ui/button"
import { DropdownMenu, DropdownMenuContent, DropdownMenuGroup, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { href, navigate } from "@/features/shell/route"
import { type Guru, TREND_RANGES, type TrendRange } from "./model"

export interface Copying {
  title: string
  variant: BadgeProps["variant"]
  /** Why it is not plainly copying, when it is not. */
  detail: string | null
}

export function GuruHeader({
  guru,
  accountId,
  onAccountChange,
  copying,
  live,
  range,
  onRangeChange,
  onRefresh,
}: {
  guru: Guru
  /** The account the figures and the chart are for. */
  accountId: string
  onAccountChange: (id: string) => void
  copying: Copying | null
  live: boolean
  range: TrendRange
  onRangeChange: (range: TrendRange) => void
  onRefresh: () => void
}) {
  return (
    <div className="flex flex-col gap-4 border-b pb-5">
      <Breadcrumb>
        <BreadcrumbList>
          <BreadcrumbItem>
            <BreadcrumbLink href={href("gurus")} className="flex items-center gap-1">
              <UsersIcon className="text-muted-foreground size-3.5" aria-hidden="true" />
              Gurus
            </BreadcrumbLink>
          </BreadcrumbItem>
          <BreadcrumbSeparator />
          <BreadcrumbItem>
            <BreadcrumbPage>{guru.name}</BreadcrumbPage>
          </BreadcrumbItem>
        </BreadcrumbList>
      </Breadcrumb>

      <div className="flex flex-wrap items-start justify-between gap-x-4 gap-y-3">
        {/* Identity */}
        <div className="flex min-w-0 flex-col gap-2.5">
          <div className="flex flex-wrap items-center gap-2.5">
            <h1 className="text-foreground text-2xl font-semibold tracking-tight">{guru.name}</h1>
            {copying && <Badge variant={copying.variant}>{copying.title}</Badge>}
            {live && <Badge variant="warning-light">Live</Badge>}
          </div>
          {guru.accounts.length > 0 && (
            <p className="text-muted-foreground inline-flex flex-wrap items-center gap-x-1.5 text-xs">
              <span>
                Copied into <span className="text-foreground font-medium">{guru.accounts.map((a) => a.id).join(", ")}</span>
              </span>
              {copying?.detail && (
                <>
                  <span className="bg-muted-foreground/40 size-1 shrink-0 rounded-full" aria-hidden="true" />
                  <span>{copying.detail}</span>
                </>
              )}
            </p>
          )}
        </div>

        {/* Actions */}
        <div className="flex shrink-0 flex-wrap items-center gap-2">
          {guru.accounts.length > 1 && (
            <Select value={accountId} onValueChange={(value) => value && onAccountChange(value)} items={guru.accounts.map((a) => ({ value: a.id, label: a.id }))}>
              <SelectTrigger className="w-[11rem]" aria-label="Account">
                <SelectValue />
              </SelectTrigger>
              <SelectContent sideOffset={9} align="end">
                {guru.accounts.map((a) => (
                  <SelectItem key={a.id} value={a.id}>
                    {a.id}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}
          {accountId && (
            <Select value={range} onValueChange={(value) => onRangeChange(value as TrendRange)} items={TREND_RANGES.map((r) => ({ value: r.value, label: r.label }))}>
              <SelectTrigger className="w-[9.5rem]" aria-label="Chart range">
                <SelectValue />
              </SelectTrigger>
              <SelectContent sideOffset={9} align="end">
                {TREND_RANGES.map((r) => (
                  <SelectItem key={r.value} value={r.value}>
                    {r.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}

          <DropdownMenu>
            <DropdownMenuTrigger render={<Button variant="ghost" size="icon" aria-label="More actions" />}>
              <EllipsisIcon aria-hidden="true" />
            </DropdownMenuTrigger>
            <DropdownMenuContent sideOffset={9} align="end" className="w-44">
              <DropdownMenuGroup>
                <DropdownMenuItem onClick={onRefresh}>
                  <RefreshCwIcon className="size-4 opacity-60" aria-hidden="true" />
                  Refresh
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => navigate("activity")}>
                  <ActivityIcon className="size-4 opacity-60" aria-hidden="true" />
                  View in Activity
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => navigate("settings", "connections")}>
                  <LinkIcon className="size-4 opacity-60" aria-hidden="true" />
                  Open Connections
                </DropdownMenuItem>
              </DropdownMenuGroup>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>
    </div>
  )
}
