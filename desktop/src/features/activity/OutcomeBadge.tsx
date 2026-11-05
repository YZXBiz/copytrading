import type { Icon } from "@/lib/icon"
import { AlertCircleIcon } from "@/components/icons/AlertCircleIcon"
import { CancelCircleIcon } from "@/components/icons/CancelCircleIcon"
import { CircleCheckIcon } from "@/components/icons/CircleCheckIcon"
import { Clock01Icon } from "@/components/icons/Clock01Icon"
import { MinusSignCircleIcon } from "@/components/icons/MinusSignCircleIcon"
import { Badge, type BadgeProps } from "@/components/reui/badge"
import { cn } from "@/lib/utils"
import type { Tone } from "./outcome"

/** The outline badge and its status dot, as ReUI's audit log (solution-users-6) marks an event's severity. */
const SEVERITY: Record<Tone, { variant: BadgeProps["variant"]; dot: string; icon: Icon }> = {
  positive: { variant: "success-outline", dot: "bg-success", icon: CircleCheckIcon },
  caution: { variant: "warning-outline", dot: "bg-warning", icon: AlertCircleIcon },
  critical: { variant: "destructive-outline", dot: "bg-destructive", icon: CancelCircleIcon },
  neutral: { variant: "info-outline", dot: "bg-info", icon: Clock01Icon },
  inactive: { variant: "outline", dot: "bg-muted-foreground", icon: MinusSignCircleIcon },
}

/** The icon that stands for a tone: on a timeline node, and beside a result's takeaway. */
export const toneIcon = (tone: Tone) => SEVERITY[tone].icon

export function OutcomeBadge({ title, tone }: { title: string; tone: Tone }) {
  const { variant, dot } = SEVERITY[tone]
  return (
    <Badge variant={variant} className="gap-1.5">
      <span className={cn("size-1.5 shrink-0 rounded-full", dot)} aria-hidden="true" />
      {title}
    </Badge>
  )
}
