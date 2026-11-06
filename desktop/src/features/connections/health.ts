import type { ProviderHealth } from "@/components/arc/provider-status/provider-status"
import type { Status } from "./state"

/**
 * How a connection's row reads: being checked, failed (the check said why), needing a look, working, or simply not checked.
 * `connection` is where its own Connect is; the status text also says "Checking…" or "Connecting" while the engine looks.
 */
export function healthOf(status: Status, connection: "idle" | "connecting" | "connected" = "idle", problem: string | null = null): ProviderHealth {
  if (connection === "connecting" || status.text === "Checking…" || status.text === "Connecting") return "checking"
  if (problem) return "outage"
  switch (status.tone) {
    case "positive":
      return "operational"
    case "caution":
      return "degraded"
    default:
      return "idle"
  }
}
