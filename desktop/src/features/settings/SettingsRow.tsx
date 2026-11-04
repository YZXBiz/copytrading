import type { ReactNode } from "react"
import { Meta } from "@/components/meta"
import { Item, ItemActions, ItemContent, ItemDescription, ItemTitle } from "@/components/ui/item"
import { cn } from "cn"

/** One row of a settings section (settings-9's preference row): what it is, a line on it only when it adds a fact, and its control or value on the right. */
export function SettingsRow({
  title,
  description,
  tone,
  stacked,
  children,
}: {
  title: ReactNode
  description?: ReactNode
  /** A caution reads in the row's own colour, so a problem stands out in a list. */
  tone?: "caution"
  /** A control too wide to sit beside the text goes under it. */
  stacked?: boolean
  children?: ReactNode
}) {
  return (
    <Item className={cn("rounded-none border-0 px-4", stacked && "flex-col items-stretch")}>
      <ItemContent className="min-w-0">
        <ItemTitle className="gap-2">{title}</ItemTitle>
        {description && (
          <ItemDescription className={cn(tone === "caution" && "text-warning-foreground dark:text-warning")}>
            {typeof description === "string" ? <Meta text={description} /> : description}
          </ItemDescription>
        )}
      </ItemContent>
      {children && <ItemActions className={cn("shrink-0", stacked && "w-full")}>{children}</ItemActions>}
    </Item>
  )
}
