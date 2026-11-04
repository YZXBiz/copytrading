import { CheckCircle2Icon, TriangleAlertIcon } from "lucide-react"
import { Alert, AlertDescription } from "@/components/reui/alert"
import { Spinner } from "@/components/ui/spinner"

/** The latest word from a long action: progress, an outcome, or a problem. */
export interface NoteState {
  kind: "working" | "done" | "problem"
  text: string
}

export function Note({ note }: { note: NoteState }) {
  const { kind, text } = note
  return (
    <Alert variant={kind === "working" ? "info" : kind === "done" ? "success" : "warning"} role={kind === "problem" ? "alert" : "status"}>
      {kind === "working" ? <Spinner /> : kind === "done" ? <CheckCircle2Icon aria-hidden /> : <TriangleAlertIcon aria-hidden />}
      <AlertDescription>{text}</AlertDescription>
    </Alert>
  )
}
