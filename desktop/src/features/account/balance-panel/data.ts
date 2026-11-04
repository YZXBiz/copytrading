import type { HistoryRange } from "../../../../shared/contract"
import { type ChartConfig } from "@/components/ui/chart"

/** The ranges the engine reads, with the name the header gives each one's change. */
export const RANGES = [
  { value: "day", label: "1D", name: "today" },
  { value: "week", label: "1W", name: "past week" },
  { value: "month", label: "1M", name: "past month" },
  { value: "three_months", label: "3M", name: "past 3 months" },
  { value: "year", label: "1Y", name: "past year" },
] as const satisfies readonly {
  value: HistoryRange
  label: string
  name: string
}[]

export type RangeKey = HistoryRange

export type ViewState = {
  range: RangeKey
  markers: boolean
  average: boolean
}

export const DEFAULT_VIEW: ViewState = {
  range: "month",
  markers: true,
  average: false,
}

export const CHART_CONFIG = {
  // The block root sets this to the primary token: one accent, win or lose.
  balance: { label: "Balance", color: "var(--chart-4-balance)" },
  average: { label: "Average", color: "var(--muted-foreground)" },
} satisfies ChartConfig

export type SeriesKey = keyof typeof CHART_CONFIG
