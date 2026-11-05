import { Alert } from "@/components/arc/alert/alert"

/** The latest word from a long action: progress, an outcome, or a problem. */
export interface NoteState {
  kind: "working" | "done" | "problem"
  text: string
}

export function Note({ note }: { note: NoteState }) {
  const { kind, text } = note
  return <Alert tone={kind === "working" ? "info" : kind === "done" ? "success" : "warning"} title={text} />
}
