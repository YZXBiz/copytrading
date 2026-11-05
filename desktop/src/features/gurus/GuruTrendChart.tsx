// solution-analytics-8's trend chart (MetricTrendChart), as shipped: a Frame with a title and description, a ComposedChart of an
// area gradient under a line with dots, and a dashed reference line for the target. Changed from the block: the data (the
// guru's cumulative realized profit by day), the target is break-even, and there is no alert-rule footer.
import { ChartLineIcon } from "@/components/icons/ChartLineIcon"
import { Area, CartesianGrid, ComposedChart, Line, ReferenceLine, XAxis, YAxis } from "recharts"
import { RegionError } from "@/components/region-error"
import { Frame, FrameDescription, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { Button } from "@/components/ui/button"
import { type ChartConfig, ChartContainer, ChartTooltip } from "@/components/ui/chart"
import { Empty, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { Skeleton } from "@/components/ui/skeleton"
import { formatSignedUsd } from "@/features/account/balance-panel/format"
import { monthDay } from "@/lib/format"
import { type TrendRow, trendAxis } from "./model"

const day = (key: string) => monthDay(`${key}T12:00:00Z`)
const axisMoney = (value: number) => `${value < 0 ? "−" : ""}$${Math.abs(value).toLocaleString("en-US", { notation: "compact", maximumFractionDigits: 1 })}`

function TrendTooltip({ active, payload, color }: { active?: boolean; payload?: { value: number; payload: TrendRow }[]; color: string }) {
  if (!active || !payload?.length) return null
  return (
    <div className="bg-popover min-w-[140px] rounded-lg border p-3 shadow-sm">
      <div className="text-muted-foreground mb-2 text-xs font-medium tracking-wide uppercase">{day(payload[0].payload.day)}</div>
      <div className="flex items-center justify-between gap-3 text-xs">
        <span className="flex items-center gap-1.5">
          <span className="size-2.5 rounded-full" style={{ backgroundColor: color }} />
          <span className="text-muted-foreground">Realized</span>
        </span>
        <span className="text-popover-foreground font-semibold tabular-nums">{formatSignedUsd(payload[0].value)}</span>
      </div>
    </div>
  )
}

export function GuruTrendChart({
  rows,
  state,
  closedTrades,
  windowed,
  onShowAll,
  onRetry,
}: {
  rows: TrendRow[]
  state: { status: "loading" } | { status: "error"; error: string } | { status: "ready" }
  closedTrades: number
  /** The chart shows a window shorter than all time. */
  windowed: boolean
  onShowAll: () => void
  onRetry: () => void
}) {
  const axis = trendAxis(rows)
  const up = (rows.at(-1)?.value ?? 0) >= 0
  const color = up ? "var(--success)" : "var(--destructive)"
  const chartConfig = { value: { label: "Realized", color } } satisfies ChartConfig
  return (
    <Frame className="h-full">
      <FrameHeader>
        <FrameTitle>Realized P&amp;L</FrameTitle>
        <FrameDescription>Cumulative profit by day against break-even</FrameDescription>
      </FrameHeader>

      <FramePanel className="flex grow flex-col">
        {state.status === "loading" && <Skeleton role="status" aria-label="Loading performance" className="h-[300px] w-full" />}
        {state.status === "error" && <RegionError title="Performance did not load" message={state.error} onRetry={onRetry} />}
        {state.status === "ready" && rows.length === 0 && (
          <Empty className="h-[300px] border-0">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ChartLineIcon aria-hidden="true" />
              </EmptyMedia>
              <EmptyTitle>{closedTrades > 0 && windowed ? "No sales closed in this range" : "No closed trades yet"}</EmptyTitle>
              <EmptyDescription>{closedTrades > 0 && windowed ? "Choose a longer range to see them." : "What this guru's sales make shows up here."}</EmptyDescription>
            </EmptyHeader>
            {closedTrades > 0 && windowed && (
              <Button type="button" size="sm" variant="outline" onClick={onShowAll}>
                Show all time
              </Button>
            )}
          </Empty>
        )}
        {state.status === "ready" && rows.length > 0 && (
          <div className="mt-auto">
            <ChartContainer config={chartConfig} className="h-[300px] w-full" role="img" aria-label={`Realized profit by day, ${formatSignedUsd(rows.at(-1)!.value)} to date.`}>
              <ComposedChart accessibilityLayer data={rows} margin={{ top: 10, right: 12, left: 0, bottom: 5 }}>
                <defs>
                  <linearGradient id="guruTrendGradient" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor={color} stopOpacity={0.18} />
                    <stop offset="100%" stopColor={color} stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid vertical={false} strokeDasharray="4 4" stroke="var(--border)" />
                <XAxis dataKey="day" axisLine={false} tickLine={false} tick={{ fontSize: 11 }} tickMargin={12} minTickGap={32} tickFormatter={day} />
                <YAxis
                  domain={axis.domain}
                  ticks={axis.ticks}
                  axisLine={false}
                  tickLine={false}
                  tick={{ fontSize: 11 }}
                  tickFormatter={axisMoney}
                  tickMargin={8}
                  width={48}
                />
                <ChartTooltip content={<TrendTooltip color={color} />} />
                <ReferenceLine y={0} stroke="var(--muted-foreground)" strokeDasharray="4 4" />
                <Area type="monotone" dataKey="value" fill="url(#guruTrendGradient)" stroke="transparent" isAnimationActive={false} />
                <Line
                  type="monotone"
                  dataKey="value"
                  stroke={color}
                  strokeWidth={2}
                  isAnimationActive={false}
                  dot={{ r: 3, fill: "var(--background)", stroke: color, strokeWidth: 2 }}
                  activeDot={{ r: 5, fill: color, stroke: "var(--background)", strokeWidth: 2 }}
                />
              </ComposedChart>
            </ChartContainer>
          </div>
        )}
      </FramePanel>
    </Frame>
  )
}
