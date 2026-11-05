import type { Icon } from "@/lib/icon"
import { AlertCircleIcon } from "@/components/icons/AlertCircleIcon"
import { CancelCircleIcon } from "@/components/icons/CancelCircleIcon"
import { CircleCheckIcon } from "@/components/icons/CircleCheckIcon"
import { Clock01Icon } from "@/components/icons/Clock01Icon"
import { MinusSignCircleIcon } from "@/components/icons/MinusSignCircleIcon"
import { Badge, type BadgeTone } from "@/components/arc/badge/badge"
import type { Tone } from "./outcome"

/** How a post ended as a badge: its tone is the status colour, with a dot. Green and red only for what went well or wrong. */
const SEVERITY: Record<Tone, { tone: BadgeTone; icon: Icon }> = {
  positive: { tone: "success", icon: CircleCheckIcon },
  caution: { tone: "warning", icon: AlertCircleIcon },
  critical: { tone: "danger", icon: CancelCircleIcon },
  neutral: { tone: "info", icon: Clock01Icon },
  inactive: { tone: "neutral", icon: MinusSignCircleIcon },
}

/** The icon that stands for a tone, beside a result's takeaway. */
export const toneIcon = (tone: Tone) => SEVERITY[tone].icon

/** The colour a tone's icon takes. */
export const toneColor: Record<Tone, string> = {
  positive: "var(--success)",
  caution: "var(--warning)",
  critical: "var(--danger)",
  neutral: "var(--accent)",
  inactive: "var(--text-muted)",
}

export function OutcomeBadge({ title, tone }: { title: string; tone: Tone }) {
  return (
    <Badge tone={SEVERITY[tone].tone} dot>
      {title}
    </Badge>
  )
}
