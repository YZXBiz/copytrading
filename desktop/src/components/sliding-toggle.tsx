import { useId, type ReactNode } from "react"
import { Toggle } from "@base-ui/react/toggle"
import { ToggleGroup } from "@base-ui/react/toggle-group"
import { motion } from "motion/react"
import { cn } from "cn"

// The pill slides on one stiff spring with no overshoot; MotionConfig's "user" setting makes it jump with Reduce motion.
const SLIDE = { type: "spring", stiffness: 1200, damping: 70 } as const

export interface SlidingOption<T extends string> {
  value: T
  label: ReactNode
  /** The spoken name when the label alone is not enough. */
  ariaLabel?: string
}

/**
 * One choice from a few, with a pill that slides to the pressed option. Arrow keys move between options, Space and Enter
 * press one, and pressing the chosen option keeps it chosen. The only motion is the pill's transform.
 */
export function SlidingToggle<T extends string>({
  value,
  onValueChange,
  options,
  label,
  disabled,
  className,
}: {
  value: T
  onValueChange: (value: T) => void
  options: readonly SlidingOption<T>[]
  /** Names the group for screen readers. */
  label: string
  disabled?: boolean
  className?: string
}) {
  const pillId = useId()
  return (
    <ToggleGroup
      value={[value]}
      onValueChange={(next) => {
        const chosen = options.find((option) => option.value === next[0])
        if (chosen && chosen.value !== value) onValueChange(chosen.value)
      }}
      aria-label={label}
      disabled={disabled}
      className={cn("border-border bg-muted/50 relative inline-flex w-fit shrink-0 items-center gap-0.5 rounded-lg border p-0.5", className)}
    >
      {options.map((option) => {
        const pressed = option.value === value
        return (
          <Toggle
            key={option.value}
            value={option.value}
            aria-label={option.ariaLabel}
            className={cn(
              "focus-visible:ring-ring/50 relative flex h-6 items-center justify-center rounded-md px-2.5 text-sm font-medium whitespace-nowrap tabular-nums outline-none transition-colors focus-visible:ring-3 disabled:pointer-events-none disabled:opacity-50",
              pressed ? "text-foreground" : "text-muted-foreground hover:text-foreground",
            )}
          >
            {pressed && <motion.span layoutId={pillId} aria-hidden="true" className="bg-background dark:bg-card ring-border/60 absolute inset-0 rounded-md shadow-xs ring-1" transition={SLIDE} />}
            <span className="relative">{option.label}</span>
          </Toggle>
        )
      })}
    </ToggleGroup>
  )
}
