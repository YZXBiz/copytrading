import type { ReactNode } from "react"
import { Sheet, SheetContent, SheetDescription, SheetFooter, SheetHeader, SheetTitle } from "@/components/ui/sheet"

/** The frame every editor shares: a side sheet with a title, a scrolling form and a footer of actions (Gumloop's setup panel). */
export function EditorSheet({
  title,
  description,
  onClose,
  footer,
  children,
}: {
  title: string
  description: string
  onClose: () => void
  footer: ReactNode
  children: ReactNode
}) {
  return (
    <Sheet open onOpenChange={(open) => !open && onClose()}>
      <SheetContent className="gap-0 data-[side=right]:sm:max-w-md">
        <SheetHeader className="border-b">
          <SheetTitle>{title}</SheetTitle>
          <SheetDescription>{description}</SheetDescription>
        </SheetHeader>
        <div className="flex flex-1 flex-col gap-6 overflow-y-auto p-4">{children}</div>
        <SheetFooter className="border-t sm:flex-row sm:justify-between">{footer}</SheetFooter>
      </SheetContent>
    </Sheet>
  )
}
