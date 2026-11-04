import { RegionError } from "@/components/region-error"
import { Badge } from "@/components/reui/badge"
import { Skeleton } from "@/components/ui/skeleton"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { useResult } from "@/lib/use-result"
import { SettingsRow } from "./SettingsRow"
import { SettingsSection } from "./SettingsSection"
import { bytes, humanCode } from "./words"

/** Whether the engine is writing its log, what it left out, and how much disk the log takes. */
export function LogHealth({ journalBytes }: { journalBytes: number | null }) {
  const status = useResult(() => window.copytrading.read.getEngineStatus(), "engine-status")
  if (status.status === "loading") return <Skeleton className="h-40 w-full" />
  if (status.status === "error") return <RegionError title="Log health did not load" message={status.error} onRetry={status.retry} />
  const engine = status.data
  const gaps = engine.diagnostic_capture
  return (
    <SettingsSection title="Log Health" hint="Each stage, post, model reply, and trade outcome, in a private file on this Mac. Keys are removed first.">
      <SettingsRow title="Logging">
        <Badge variant={engine.telemetry_state === "healthy" ? "success-light" : "warning-light"}>{engine.telemetry_state === "healthy" ? "Healthy" : "Degraded"}</Badge>
      </SettingsRow>
      {engine.telemetry_error_code && <SettingsRow title="Last problem" description={humanCode(engine.telemetry_error_code)} tone="caution" />}
      <SettingsRow title="Records dropped">{engine.telemetry_dropped.toLocaleString("en-US")}</SettingsRow>
      {gaps && (
        <SettingsRow title="Left out (posts / requests / replies)">
          <Tooltip>
            <TooltipTrigger type="button" className="cursor-help tabular-nums">
              {`${gaps.source_event_gaps} / ${gaps.model_request_gaps} / ${gaps.model_response_gaps}`}
            </TooltipTrigger>
            <TooltipContent>A record too large to keep, or one that could not be cleaned of keys safely.</TooltipContent>
          </Tooltip>
        </SettingsRow>
      )}
      {journalBytes !== null && <SettingsRow title="On disk">{bytes(journalBytes)}</SettingsRow>}
    </SettingsSection>
  )
}
