import type { HistoryRange } from "../../../../shared/contract"

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

export const DEFAULT_RANGE: HistoryRange = "month"
