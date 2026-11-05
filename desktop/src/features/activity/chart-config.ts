import type { ChartConfig } from "@/components/ui/chart"

/** The four outcomes in the accent's family, traded first; waiting is the app's one warm colour, and red and green stay for gain and loss. */
export const OUTCOME_CONFIG = {
  traded: { label: "Traded", color: "var(--chart-1)" },
  waiting: { label: "Waiting", color: "var(--warning)" },
  skipped: { label: "Skipped", color: "var(--chart-4)" },
  ignored: { label: "Ignored", color: "var(--muted-foreground)" },
} satisfies ChartConfig

export const COUNT_CONFIG = { count: { label: "Posts", color: "var(--chart-4)" } } satisfies ChartConfig
