import type { ManualOrderPreview } from "../../../shared/contract"
import { Alert, AlertDescription } from "@/components/reui/alert"
import { Badge } from "@/components/reui/badge"
import { Meta } from "@/components/meta"
import { type Outcome, outcomeProblems, previewDetail, previewHeadline, previewProblems, previewStatus, previewWarnings } from "./manual-preview"

/** What the engine says one drafted trade would place in one account: the order, or why it can't go, then what became of it once sent. */
export function PreviewRow({
  accountId,
  index,
  preview,
  error,
  outcome,
}: {
  accountId: string
  index: number
  preview: ManualOrderPreview | null
  /** The check itself failed (the engine could not be asked). */
  error: string | null
  outcome: Outcome | undefined
}) {
  const status = previewStatus(preview, outcome, error !== null)
  const problems = [...(preview ? previewProblems(preview) : []), ...(error ? [error] : []), ...outcomeProblems(outcome)]
  const warnings = preview ? previewWarnings(preview) : []
  return (
    <li className="flex flex-col gap-1 py-2">
      <div className="flex items-baseline justify-between gap-3">
        <span className="font-medium tabular-nums">{previewHeadline(preview, accountId, index)}</span>
        {status && <Badge variant={status.tone}>{status.text}</Badge>}
      </div>
      {preview && <Meta className="text-muted-foreground text-xs tabular-nums" items={previewDetail(preview)} />}
      {[...new Set(problems)].map((problem) => (
        <p key={problem} role="alert" className="text-destructive text-xs">
          {problem}
        </p>
      ))}
      {warnings.map((warning) => (
        <Alert key={warning} variant="warning">
          <AlertDescription>{warning}</AlertDescription>
        </Alert>
      ))}
    </li>
  )
}
