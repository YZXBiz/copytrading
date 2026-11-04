import { Fragment, type ReactNode } from "react"
import { cn } from "@/lib/utils"

const SEPARATOR = " · "

/** The facts of one engine string: split at " · ", empty ones dropped. */
export const metaSegments = (text: string): string[] => text.split(SEPARATOR).filter((s) => s !== "")

/**
 * A line of meta facts with the house inline separator between them, never a typed dot.
 * Pass the segments, or one engine string whose segments are joined by " · " (it is split here);
 * a string with line breaks becomes one line per row.
 */
export function Meta({ items, text, className }: { items?: ReactNode[]; text?: string; className?: string }) {
  if (text?.includes("\n")) {
    return (
      <span className={cn("flex flex-col gap-0.5", className)}>
        {text.split("\n").map((line, i) => (
          <Meta key={i} text={line} />
        ))}
      </span>
    )
  }
  const segments = (items ?? (text ? metaSegments(text) : [])).filter((s) => s !== null && s !== undefined && s !== false && s !== "")
  return (
    <span className={cn("inline-flex min-w-0 flex-wrap items-center gap-x-2 gap-y-0.5", className)}>
      {segments.map((segment, i) => (
        <Fragment key={i}>
          {i > 0 && <span aria-hidden className="bg-muted-foreground/40 size-1 shrink-0 rounded-full" />}
          <span className="min-w-0">{segment}</span>
        </Fragment>
      ))}
    </span>
  )
}
