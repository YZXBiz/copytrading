import type { ManualOrderPreview } from "../../../shared/contract"
import { Alert } from "@/components/arc/alert/alert"
import { Badge } from "@/components/arc/badge/badge"
import { Meta } from "@/components/meta"
import { type Outcome, outcomeProblems, previewDetail, previewHeadline, previewProblems, previewStatus, previewWarnings } from "./manual-preview"
import styles from "./sheet.module.css"

const TONE = { "success-light": "success", "warning-light": "warning", "destructive-light": "danger", "info-light": "info", outline: "neutral" } as const

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
    <li className={styles.preview}>
      <div className={styles.previewHead}>
        <span className={styles.previewTitle}>{previewHeadline(preview, accountId, index)}</span>
        {status && <Badge tone={TONE[status.tone as keyof typeof TONE] ?? "neutral"}>{status.text}</Badge>}
      </div>
      {preview && <Meta className={styles.hint} items={previewDetail(preview)} />}
      {[...new Set(problems)].map((problem) => (
        <p key={problem} role="alert" className={styles.problem}>
          {problem}
        </p>
      ))}
      {warnings.map((warning) => (
        <Alert key={warning} tone="warning" title={warning} />
      ))}
    </li>
  )
}
