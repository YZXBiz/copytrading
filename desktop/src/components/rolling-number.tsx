import type { ComponentProps } from "react"
import { easeOut, useReducedMotion } from "motion/react"
import { AnimateNumber } from "@/components/animate-number"

// A figure rolls on a spring with no overshoot and is still within 0.6 s.
const ROLL = { y: { type: "spring", duration: 0.6, bounce: 0 }, width: { type: "spring", duration: 0.6, bounce: 0 }, opacity: { duration: 0.6, ease: easeOut } } as const
// A readout that follows the pointer changes with every move, so it rolls faster than a figure that changes on a refresh.
const QUICK_TWEEN = { type: "tween", duration: 0.25, ease: easeOut } as const
const QUICK = { y: QUICK_TWEEN, width: QUICK_TWEEN, opacity: QUICK_TWEEN } as const

type Format = NonNullable<ComponentProps<typeof AnimateNumber>["format"]>

/**
 * A figure whose digits roll to a new value, in the direction it moved. The first render shows the number as it is;
 * macOS "Reduce motion" shows each new value at once as plain text. The text is the formatter's own: pass the same
 * `Intl` options the page formats with (`balance-panel/format.ts`). A missing or non-numeric value reads as a dash.
 */
export function RollingNumber({
  value,
  format,
  className,
  quick,
}: {
  value: number | null | undefined
  format: Format
  className?: string
  quick?: boolean
}) {
  const reduced = useReducedMotion()
  if (value === null || value === undefined || !Number.isFinite(value)) return <span className={className}>—</span>
  if (reduced) return <span className={className}>{new Intl.NumberFormat("en-US", format).format(value)}</span>
  return (
    <AnimateNumber data-rolling="" style={{ lineHeight: "inherit" }} locales="en-US" format={format} className={className} transition={quick ? QUICK : ROLL}>
      {value}
    </AnimateNumber>
  )
}
