import type { ReactNode } from "react"
import { Meta } from "@/components/meta"
import { Sheet, SheetContent, SheetDescription, SheetFooter, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { cn } from "@/lib/utils"

/**
 * The frame every editor shares: a side sheet with a title, a scrolling form and a footer of actions (Gumloop's setup panel).
 * `description` names the sheet for screen readers; it shows only when `showDescription` says it carries a fact the owner needs.
 */
export function EditorSheet({
  title,
  description,
  showDescription = false,
  onClose,
  footer,
  children,
}: {
  title: string
  description: string
  showDescription?: boolean
  onClose: () => void
  footer: ReactNode
  children: ReactNode
}) {
  return (
    <Sheet open onOpenChange={(open) => !open && onClose()}>
      <SheetContent className="gap-0 data-[side=right]:sm:max-w-md">
        <SheetHeader className="border-b">
          <SheetTitle>{title}</SheetTitle>
          <SheetDescription className={cn(!showDescription && "sr-only")}>
            <Meta text={description} />
          </SheetDescription>
        </SheetHeader>
        <div className="flex flex-1 flex-col gap-6 overflow-y-auto p-4">{children}</div>
        <SheetFooter className="border-t sm:flex-row sm:justify-between">{footer}</SheetFooter>
      </SheetContent>
    </Sheet>
  )
}
