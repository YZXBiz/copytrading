import { Alert } from "@/components/arc/alert/alert"
import { Button } from "@/components/arc/button/button"
import { type CheckResult, type Subject } from "./state"
import { checkDetail, connectionProblem } from "./words"

/**
 * What a connection's last check found, in words: connected, or what to fix. `modelName` is what was checked, for "has no
 * model called …"; `useModel` puts the engine's closest model name into the form. `notice` is why Connect had nothing to check.
 */
export function CheckNotice({
  subject,
  result,
  notice,
  modelName = "",
  useModel,
}: {
  subject: Subject
  result: CheckResult | undefined
  notice?: string
  modelName?: string
  useModel?: (name: string) => void
}) {
  if (notice) {
    return (
      <Alert tone="warning" title="Nothing to check yet" data-subject={subject}>
        {notice}
      </Alert>
    )
  }
  if (!result) return null
  const { check, error } = result
  if (!check) return <Alert tone="info" title="Checking" aria-busy="true" />
  if (check.state === "ready") {
    const detail = checkDetail(check, modelName)
    return (
      <Alert tone="info" title="Connected">
        {detail || undefined}
      </Alert>
    )
  }
  return (
    <Alert tone="danger" title="Could not connect">
      {error ?? connectionProblem(check, modelName)}
      {check.suggestion && useModel && (
        <div style={{ marginTop: 8 }}>
          <Button type="button" size="sm" variant="secondary" onClick={() => useModel(check.suggestion!)}>
            Use {check.suggestion}
          </Button>
        </div>
      )}
    </Alert>
  )
}
