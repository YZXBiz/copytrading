import { Badge } from "@/components/arc/badge/badge"
import { Tooltip } from "@/components/arc/tooltip/tooltip"
import { useResult } from "@/lib/use-result"
import { SectionError } from "./SectionError"
import { SettingsRow } from "./SettingsRow"
import styles from "./settings.module.css"
import { SectionSkeleton, SettingsSection } from "./SettingsSection"
import { bytes, humanCode } from "./words"

/** Whether the engine is writing its log, what it left out, and how much disk the log takes. */
export function LogHealth({ journalBytes }: { journalBytes: number | null }) {
  const status = useResult(() => window.copytrading.read.getEngineStatus(), "engine-status")
  if (status.status === "loading") return <SectionSkeleton rows={4} label="Loading log health" />
  if (status.status === "error") return <SectionError title="Log health did not load" message={status.error} onRetry={status.retry} />
  const engine = status.data
  const gaps = engine.diagnostic_capture
  return (
    <SettingsSection title="Log health" hint="Stages, posts and trades, in a private file here.">
      <SettingsRow title="Logging">
        <Badge tone={engine.telemetry_state === "healthy" ? "success" : "warning"}>{engine.telemetry_state === "healthy" ? "Healthy" : "Degraded"}</Badge>
      </SettingsRow>
      {engine.telemetry_error_code && <SettingsRow title="Last problem" description={humanCode(engine.telemetry_error_code)} tone="caution" />}
      <SettingsRow title="Records dropped"><span className={styles.value}>{engine.telemetry_dropped.toLocaleString("en-US")}</span></SettingsRow>
      {gaps && (
        <SettingsRow title="Left out (posts, requests, replies)">
          <Tooltip content="A record too large to keep, or one that could not be cleaned of keys safely.">
            <button type="button" className={styles.value} style={{ border: 0, background: "none", padding: 0, cursor: "help" }}>
              {`${gaps.source_event_gaps} / ${gaps.model_request_gaps} / ${gaps.model_response_gaps}`}
            </button>
          </Tooltip>
        </SettingsRow>
      )}
      {journalBytes !== null && <SettingsRow title="On disk"><span className={styles.value}>{bytes(journalBytes)}</span></SettingsRow>}
    </SettingsSection>
  )
}
