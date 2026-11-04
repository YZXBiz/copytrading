import { CircleAlertIcon, CircleCheckIcon } from "lucide-react"
import { Alert, AlertAction, AlertDescription, AlertTitle } from "@/components/reui/alert"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
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
      <Alert variant="warning" data-subject={subject}>
        <CircleAlertIcon aria-hidden />
        <AlertTitle>Nothing to check yet</AlertTitle>
        <AlertDescription>{notice}</AlertDescription>
      </Alert>
    )
  }
  if (!result) return null
  const { check, error } = result
  if (!check) {
    return (
      <p className="text-muted-foreground flex items-center gap-2 text-sm">
        <Spinner /> Checking…
      </p>
    )
  }
  if (check.state === "ready") {
    return (
      <Alert variant="success">
        <CircleCheckIcon aria-hidden />
        <AlertTitle>Connected</AlertTitle>
        {checkDetail(check, modelName) && <AlertDescription>{checkDetail(check, modelName)}</AlertDescription>}
      </Alert>
    )
  }
  return (
    <Alert variant="destructive">
      <CircleAlertIcon aria-hidden />
      <AlertTitle>Couldn't connect</AlertTitle>
      <AlertDescription>{error ?? connectionProblem(check, modelName)}</AlertDescription>
      {check.suggestion && useModel && (
        <AlertAction>
          <Button type="button" size="xs" variant="outline" onClick={() => useModel(check.suggestion!)}>
            Use {check.suggestion}
          </Button>
        </AlertAction>
      )}
    </Alert>
  )
}
