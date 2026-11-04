import type { LucideIcon } from "lucide-react"
import { Meta } from "@/components/meta"
import { Button } from "@/components/ui/button"
import { Item, ItemActions, ItemContent, ItemDescription, ItemMedia, ItemTitle } from "@/components/ui/item"
import { Spinner } from "@/components/ui/spinner"
import { StatusBadge } from "./StatusBadge"
import type { Status } from "./state"

/** One service, account or guru in Connections: what it is, how it is doing, and Connect or Edit (Item with a status badge, c-item-5). */
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
    <Item size="sm" role="listitem" className="rounded-none border-0">
      <ItemMedia variant="icon">
        <Icon aria-hidden />
      </ItemMedia>
      <ItemContent>
        <ItemTitle>{title}</ItemTitle>
        {detail && (
          <ItemDescription>
            <Meta text={detail} />
          </ItemDescription>
        )}
        {problem && <p className="text-destructive text-xs">{problem}</p>}
      </ItemContent>
      <ItemActions>
        <StatusBadge status={status} />
        {onConnect && (
          <Button type="button" size="xs" variant="outline" disabled={checking} onClick={onConnect} aria-label={`${connectLabel} ${label}`}>
            {checking && <Spinner className="size-3" />}
            {connectLabel}
          </Button>
        )}
        <Button type="button" size="xs" variant="ghost" onClick={onEdit} aria-label={`Edit ${label}`}>
          Edit
        </Button>
      </ItemActions>
    </Item>
  )
}
