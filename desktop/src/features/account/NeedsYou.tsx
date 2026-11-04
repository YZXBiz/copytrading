import { BellIcon } from "lucide-react"
import type { SourceActivity } from "../../../shared/contract"
import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert"

/** The notice above the stats when guru posts wait for a decision. Nothing waiting, nothing shown. */
export function NeedsYou({ waiting }: { waiting: SourceActivity[] }) {
  if (waiting.length === 0) return null
  const gurus = [...new Set(waiting.map((p) => p.guru_id).filter(Boolean))].join(", ")
  return (
    <Alert variant="warning">
      <BellIcon aria-hidden="true" />
      <AlertTitle>{waiting.length === 1 ? "1 post waits for you" : `${waiting.length} posts wait for you`}</AlertTitle>
      <AlertDescription>
        {gurus ? `${gurus} posted` : "Posted"} calls CopyTrading cannot size on its own. Nothing is bought or sold for them until they are reviewed.
      </AlertDescription>
    </Alert>
  )
}
