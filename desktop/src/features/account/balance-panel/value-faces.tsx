import { type ReactNode } from "react"
import { Badge } from "@/components/reui/badge"
import { cn } from "@/lib/utils"

import { type SeriesKey } from "./data"
import { formatSignedPercent } from "./format"
import { BADGE_TREND_ICONS } from "./icons"

/** The balance line's colour on the block root: the app's one accent, the
 *  primary token, win or lose (the change badge carries the sign).
 *  Every surface reads `--chart-4-balance`. */
export const ACCENT_SCOPE = "[--chart-4-balance:var(--primary)]"

/** Trims a label to its caps, so `items-center` lines the letters up with
 *  the dot or control beside it. Needs a fixed-height row. */
export const CAP_BOX = "[text-box:trim-both_cap_alphabetic]"

export function DotSeparator() {
  return (
    <span
      aria-hidden="true"
      className="bg-muted-foreground/40 size-1 shrink-0 rounded-full"
    />
  )
}

/** A short stroke key, dashed the way its line is: a CSS dashed border
 *  shows one dash at this size, so the key draws its own stroke. */
function StrokeKey({
  dashed,
  weight,
  className,
}: {
  dashed: boolean
  weight: number
  className: string
}) {
  return (
    <svg
      aria-hidden="true"
      width={12}
      height={weight}
      viewBox={`0 0 12 ${weight}`}
      className={cn("shrink-0 overflow-visible", className)}
    >
      <line
        x1={0}
        x2={12}
        y1={weight / 2}
        y2={weight / 2}
        stroke="currentColor"
        strokeWidth={weight}
        strokeDasharray={dashed ? "3 2" : undefined}
        strokeLinecap={dashed ? "butt" : "round"}
      />
    </svg>
  )
}

/** The balance line's key: a solid stroke in its colour. */
export function SeriesKeyMark({ series }: { series: SeriesKey }) {
  return series === "balance" ? (
    <StrokeKey dashed={false} weight={2} className="text-(--chart-4-balance)" />
  ) : (
    <AverageKey />
  )
}

/** The average line's key: a thin dashed rule in the muted tone. */
export function AverageKey() {
  return <StrokeKey dashed weight={1} className="text-muted-foreground" />
}

/** A text-xs fact on a status line: cap-trimmed inside an h-4 row. */
export function Fact({
  children,
  className,
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <span className={cn("flex h-4 items-center", className)}>
      <span className={CAP_BOX}>{children}</span>
    </span>
  )
}

/** A change reads as state: up is good for a balance. */
export function ChangeBadge({ ratio }: { ratio: number }) {
  const up = ratio >= 0
  return (
    <Badge variant={up ? "success-light" : "destructive-light"}>
      {up ? BADGE_TREND_ICONS.up : BADGE_TREND_ICONS.down}
      <span className={cn(CAP_BOX, "tabular-nums")}>
        {formatSignedPercent(ratio)}
      </span>
    </Badge>
  )
}
