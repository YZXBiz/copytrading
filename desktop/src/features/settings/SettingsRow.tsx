import type { ReactNode } from "react"
import { Item, ItemActions, ItemContent, ItemDescription, ItemTitle } from "@/components/ui/item"
import { cn } from "cn"

/** One row of a settings section: what it is, one line on it, and its control or value on the right. */
export function SettingsRow({
  title,
  description,
  tone,
  children,
}: {
  title: ReactNode
  description?: ReactNode
  /** A caution reads in the row's own colour, so a problem stands out in a list. */
  tone?: "caution"
  children?: ReactNode
}) {
  return (
    <Item size="sm" className="rounded-none border-0">
      <ItemContent>
        <ItemTitle>{title}</ItemTitle>
        {description && <ItemDescription className={cn("whitespace-pre-line", tone === "caution" && "text-warning-foreground dark:text-warning")}>{description}</ItemDescription>}
      </ItemContent>
      {children && <ItemActions>{children}</ItemActions>}
    </Item>
  )
}
