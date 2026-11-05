import { motion, useReducedMotion } from "motion/react"
import { sparkPath } from "@/lib/sparkline"
import { cn } from "@/lib/utils"

const W = 96
const H = 40

/**
 * A line through `values` that draws itself in once, when it first appears. A later change of values moves the line at
 * once and never draws it again; with Reduce motion it is simply there. Colour comes from `className` (a stroke class).
 */
export function KpiSparkline({ values, className }: { values: number[]; className?: string }) {
  const reduced = useReducedMotion()
  const d = sparkPath(values, W, H)
  if (!d) return null
  return (
    <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" aria-hidden="true" className={cn("h-10 w-24 overflow-visible", className)}>
      <motion.path
        d={d}
        fill="none"
        stroke="currentColor"
        strokeWidth={1.5}
        strokeLinecap="round"
        strokeLinejoin="round"
        vectorEffect="non-scaling-stroke"
        initial={reduced ? false : { pathLength: 0 }}
        animate={{ pathLength: 1 }}
        transition={{ duration: 0.9, ease: [0.22, 1, 0.36, 1] }}
      />
    </svg>
  )
}
