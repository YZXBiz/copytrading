import type { LucideIcon } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Item, ItemActions, ItemContent, ItemDescription, ItemMedia, ItemTitle } from "@/components/ui/item"
import { Spinner } from "@/components/ui/spinner"
import { StatusBadge } from "./StatusBadge"
import type { Status } from "./state"

/** One service, account or guru in Connections: the row of ReUI's settings-16 (Connected Apps). Logo tile, name with its status badge, one line of detail, then Connect and Edit. */
export function ConnectionRow({
  icon: Icon,
  title,
  detail,
  status,
  problem,
  onEdit,
  onConnect,
  connectLabel = "Connect",
  checking = false,
  label,
}: {
  icon: LucideIcon
  title: string
  detail?: string
  status: Status
  /** Why the last check failed, in words. */
  problem?: string | null
  onEdit: () => void
  /** Absent for a row with nothing to check, such as a guru. */
  onConnect?: () => void
  connectLabel?: string
  checking?: boolean
  /** Names the row for the buttons' accessible names, such as "Discord". */
  label: string
}) {
  return (
    <Item role="listitem" className="items-center px-3.5 py-2.5 sm:px-4">
      <ItemMedia className="translate-y-0! self-center!">
        <Item className="bg-muted/60 border-background flex size-10 shrink-0 items-center justify-center border-2 p-0 shadow-[0_1px_3px_0_rgba(0,0,0,0.14)] dark:border [&_svg]:block [&_svg]:size-5">
          <ItemMedia variant="icon" className="size-auto translate-y-0! self-center!">
            <Icon aria-hidden />
          </ItemMedia>
        </Item>
      </ItemMedia>
      <ItemContent className="min-w-0 gap-0">
        <ItemTitle className="w-full min-w-0 gap-2">
          <span className="truncate">{title}</span>
          <StatusBadge status={status} />
        </ItemTitle>
        {detail && <ItemDescription className="line-clamp-1">{detail}</ItemDescription>}
        {problem && <p className="text-destructive line-clamp-2 text-xs">{problem}</p>}
      </ItemContent>
      <ItemActions className="ml-auto shrink-0 justify-end gap-2">
        {onConnect && (
          <Button type="button" size="sm" variant="outline" disabled={checking} onClick={onConnect} aria-label={`${connectLabel} ${label}`}>
            {checking && <Spinner className="size-3" />}
            {connectLabel}
          </Button>
        )}
        <Button type="button" size="sm" variant="ghost" onClick={onEdit} aria-label={`Edit ${label}`}>
          Edit
        </Button>
      </ItemActions>
    </Item>
  )
}
