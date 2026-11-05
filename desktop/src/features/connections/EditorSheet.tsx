import type { ReactNode } from "react"
import type { Icon } from "@/lib/icon"
import { IconTile } from "@/components/reui/icon-tile"
import { Sheet, SheetContent, SheetDescription, SheetFooter, SheetHeader, SheetTitle } from "@/components/ui/sheet"

/**
 * The frame every editor shares, in the shape of ReUI's connection sheets (sheet-22, sheet-23): a header band with the
 * kind's icon tile, the title and one line on it, a scrolling form, and a footer of actions.
 */
export function EditorSheet({
  icon: Icon,
  title,
  description,
  onClose,
  footer,
  children,
}: {
  icon: Icon
  title: string
  description: string
  onClose: () => void
  footer: ReactNode
  children: ReactNode
}) {
  return (
    <Sheet open onOpenChange={(open) => !open && onClose()}>
      <SheetContent className="gap-0 data-[side=right]:sm:max-w-md">
        <SheetHeader className="flex-row items-center gap-3 border-b px-5 py-3 pr-12">
          <IconTile variant="elevated" aria-hidden="true">
            <Icon />
          </IconTile>
          <div className="flex min-w-0 flex-col gap-0.5">
            <SheetTitle className="truncate">{title}</SheetTitle>
            <SheetDescription className="line-clamp-2">{description}</SheetDescription>
          </div>
        </SheetHeader>
        <div className="flex flex-1 flex-col gap-6 overflow-y-auto px-5 py-4">{children}</div>
        <SheetFooter className="border-t px-5 py-3 sm:flex-row sm:justify-between">{footer}</SheetFooter>
      </SheetContent>
    </Sheet>
  )
}
