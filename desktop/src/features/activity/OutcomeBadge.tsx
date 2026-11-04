import { CheckCircle2Icon, CircleAlertIcon, ClockIcon, MinusCircleIcon, XCircleIcon, type LucideIcon } from "lucide-react"
import { Badge, type BadgeProps } from "@/components/reui/badge"
import { cn } from "@/lib/utils"
import type { Tone } from "./outcome"

/** The outline badge and its status dot, as ReUI's audit log (solution-users-6) marks an event's severity. */
const SEVERITY: Record<Tone, { variant: BadgeProps["variant"]; dot: string; icon: LucideIcon }> = {
  positive: { variant: "success-outline", dot: "bg-success", icon: CheckCircle2Icon },
  caution: { variant: "warning-outline", dot: "bg-warning", icon: CircleAlertIcon },
  critical: { variant: "destructive-outline", dot: "bg-destructive", icon: XCircleIcon },
  neutral: { variant: "info-outline", dot: "bg-info", icon: ClockIcon },
  inactive: { variant: "outline", dot: "bg-muted-foreground", icon: MinusCircleIcon },
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
