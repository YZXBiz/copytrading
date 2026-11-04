import { Badge } from "@/components/reui/badge"
import type { Status } from "./state"

const VARIANT = { positive: "success-light", caution: "warning-light", inactive: "outline", neutral: "secondary" } as const

/** A connection's state as a word and a tone (the Badge's own variants; no colors chosen here). */
export function StatusBadge({ status }: { status: Status }) {
  return <Badge variant={VARIANT[status.tone]}>{status.text}</Badge>
}
