import { useMemo } from "react"
import { ChartLineIcon } from "@/components/icons/ChartLineIcon"
import { Button } from "@/components/arc/button/button"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { LineChart, type LineChartDatum } from "@/components/arc/line-chart/line-chart"
import SegmentedControl from "@/components/arc/segmented-control/segmented-control"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import { RegionAlert } from "@/features/activity/RegionAlert"
import { formatSignedUsd } from "@/features/account/balance-panel/format"
import { monthDay } from "@/lib/format"
import { TREND_RANGES, type TrendRange, type TrendRow } from "./model"
import styles from "./gurus.module.css"

const day = (key: string) => monthDay(`${key}T12:00:00Z`)
const axisMoney = (value: number) => `${value < 0 ? "−" : ""}$${Math.abs(value).toLocaleString("en-US", { notation: "compact", maximumFractionDigits: 1 })}`
const RANGES = TREND_RANGES.map((r) => ({ value: r.value, label: r.label }))

/** The guru's cumulative realized profit by day against break-even, over the range chosen. */
export function GuruTrendChart({
  rows,
  state,
  closedTrades,
  windowed,
  range,
  onRangeChange,
  onShowAll,
  onRetry,
}: {
  rows: TrendRow[]
  state: { status: "loading" } | { status: "error"; error: string } | { status: "ready" }
  closedTrades: number
  /** The chart shows a window shorter than all time. */
  windowed: boolean
  range: TrendRange
  onRangeChange: (range: TrendRange) => void
  onShowAll: () => void
  onRetry: () => void
}) {
  const up = (rows.at(-1)?.value ?? 0) >= 0
  const color = up ? "var(--success)" : "var(--danger)"
  const series = useMemo(
    () => [
      { key: "realized", label: "Realized", color, area: true },
      { key: "breakeven", label: "Break-even", color: "var(--text-muted)", dashed: true, area: false },
    ],
    [color],
  )
  // The same array until the rows change: the page re-reads every few seconds and a new one would redraw the line.
  const data = useMemo<LineChartDatum[]>(
    () => rows.map((row, index) => ({ key: row.day, label: day(row.day), axisLabel: index % Math.max(1, Math.ceil(rows.length / 6)) === 0 ? day(row.day) : undefined, values: { realized: row.value, breakeven: 0 } })),
    [rows],
  )
  const shortRange = closedTrades > 0 && windowed
  return (
    <section className={styles.panel} aria-labelledby="realized-title">
      <div className={styles.panelHeader}>
        <div className={styles.panelHead}>
          <h2 id="realized-title">Realized P&amp;L</h2>
          <p>Cumulative profit by day against break-even</p>
        </div>
        <SegmentedControl label="Chart range" options={RANGES} value={range} onValueChange={(value) => onRangeChange(value as TrendRange)} />
      </div>
      {state.status === "loading" && <Skeleton label="Loading performance" lines={5} className={styles.chartBlock} />}
      {state.status === "error" && <RegionAlert title="Performance did not load" message={state.error} onRetry={onRetry} />}
      {state.status === "ready" && rows.length === 0 && (
        <EmptyState
          icon={<ChartLineIcon width={24} height={24} aria-hidden="true" />}
          title={shortRange ? "No sales closed in this range" : "No closed trades yet"}
          description={shortRange ? "Choose a longer range to see them." : "What this guru's sales make shows up here."}
          action={
            shortRange ? (
              <Button variant="secondary" size="sm" onClick={onShowAll}>
                Show all time
              </Button>
            ) : undefined
          }
        />
      )}
      {state.status === "ready" && rows.length > 0 && (
        <LineChart
          data={data}
          series={series}
          label={`Realized profit by day, ${formatSignedUsd(rows.at(-1)!.value)} to date`}
          height={260}
          categoryLabel="Day"
          formatTick={axisMoney}
          formatValue={(value) => formatSignedUsd(value)}
        />
      )}
    </section>
  )
}
