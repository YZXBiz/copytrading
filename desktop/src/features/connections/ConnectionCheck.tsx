import { Alert } from "@/components/arc/alert/alert"
import { Button } from "@/components/arc/button/button"
import { ConnectorSetup, type Connector } from "@/components/arc/connector-setup/connector-setup"
import type { Icon } from "@/lib/icon"
import { connect, useSetup } from "./setup-store"
import { type Subject, resultFor } from "./state"
import { checkDetail, connectionProblem } from "./words"

/**
 * The Connect flow of an editor sheet: one card with the service, what connecting does, and where its check stands.
 * Connect checks the service with what is typed before anything is saved, and the card ends as "Connected" with what the
 * check found, or the reason it failed with Try again. `useModel` puts the engine's closest model name into the form.
 * A Connect with nothing to check yet says what is missing instead.
 */
export function ConnectionCheck({
  subject,
  name,
  icon: Mark,
  description,
  modelName = "",
  useModel,
}: {
  subject: Subject
  /** The service as the owner knows it: "Discord". */
  name: string
  icon: Icon
  /** What connecting does, in one line. */
  description: string
  modelName?: string
  useModel?: (name: string) => void
}) {
  const s = useSetup()
  const result = resultFor(s.checks, s.draft, subject)
  const notice = s.notices[subject]
  const check = result?.check
  const failed = Boolean(check && check.state !== "ready")

  const connector: Connector = {
    id: subject,
    name,
    description,
    mark: <Mark width={20} height={20} aria-hidden="true" />,
    status: !result ? "available" : check === null ? "connecting" : failed ? "error" : "connected",
    step: `Checking ${name}`,
    result: check && !failed ? checkDetail(check, modelName) || `${name} answered` : undefined,
    problem: check && failed ? (result?.error ?? connectionProblem(check, modelName)) : undefined,
  }

  return (
    <div style={{ display: "grid", gap: 12 }}>
      {notice && (
        <Alert tone="warning" title="Nothing to check yet" data-subject={subject}>
          {notice}
        </Alert>
      )}
      <ConnectorSetup
        title="Connection"
        description="Connect checks the service with what is typed here."
        connectors={[connector]}
        onConnect={() => void connect(subject)}
      />
      {check?.suggestion && failed && useModel && (
        <div>
          <Button type="button" size="sm" variant="secondary" onClick={() => useModel(check.suggestion!)}>
            Use {check.suggestion}
          </Button>
        </div>
      )}
    </div>
  )
}
