import type { ReactNode } from "react"
import { cn } from "@/lib/utils"

/** The facts of one engine string: split at " · " or a line break, empty ones dropped. */
export const metaSegments = (text: string): string[] => text.split(/ · |\n/).filter((s) => s.trim() !== "")

/**
 * Facts, one to a line: position does the separating, never a typed or drawn dot.
 * Pass the facts as `items`, or one engine string whose facts are joined by " · " or line breaks (it is split here).
 */
export function Meta({ items, text, className }: { items?: ReactNode[]; text?: string; className?: string }) {
  const facts = (items ?? (text ? metaSegments(text) : [])).filter((s) => s !== null && s !== undefined && s !== false && s !== "")
  return (
    <span className={cn("flex min-w-0 flex-col gap-0.5", className)}>
      {facts.map((fact, i) => (
        <span key={i} className="min-w-0">
          {fact}
        </span>
      ))}
    </span>
  )
}
