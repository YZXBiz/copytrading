import type { TradingRunState } from "./contract"

/** How each state of copying reads, and which tone marks it: the sidebar footer's dot and the menu bar item's dot say the same. */
export type Tone = "success" | "warning" | "idle" | "destructive"

export const COPYING_STATES: Record<TradingRunState, { label: string; tone: Tone }> = {
  running: { label: "Copying", tone: "success" },
  starting: { label: "Starting", tone: "warning" },
  degraded: { label: "Copying, with problems", tone: "warning" },
  pausing: { label: "Pausing", tone: "warning" },
  paused: { label: "Not copying", tone: "idle" },
  failed: { label: "Stopped by an error", tone: "destructive" },
}
