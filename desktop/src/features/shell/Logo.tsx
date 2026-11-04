import { TrendingUpIcon } from "lucide-react"
import { cn } from "@/lib/utils"
import { Item, ItemMedia } from "@/components/ui/item"

/** app-shell-2's logo tile, with the app's glyph in place of ReUI's mark. */
export function Logo({ className }: { className?: string }) {
  return (
    <span className={cn("relative flex size-7 shrink-0 items-center justify-center", className)}>
      <Item
        className={cn(
          "p-0",
          "bg-primary text-primary-foreground flex size-8 shrink-0 items-center justify-center",
          "absolute top-1/2 left-1/2 origin-center -translate-x-1/2 -translate-y-1/2 scale-[0.875]",
        )}
        aria-hidden="true"
      >
        <ItemMedia variant="icon" className="size-auto">
          <TrendingUpIcon className="size-4" />
        </ItemMedia>
      </Item>
    </span>
  )
}
