import { Badge } from "@/components/arc/badge/badge"
import type { Status } from "./state"

// A good state reads in the accent: green belongs to gains, so it is never used for a connection.
const TONE = { positive: "info", caution: "warning", inactive: "neutral", neutral: "neutral" } as const

/** A connection's state as a word and a tone. */
export function StatusBadge({ status }: { status: Status }) {
  return (
    <Badge tone={TONE[status.tone]} outline={status.tone === "inactive"} size="sm">
      {status.text}
    </Badge>
  )
}
