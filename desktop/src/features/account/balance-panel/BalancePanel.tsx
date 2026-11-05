// dashboard-8's chart panel (RevenueChart: a Frame whose header holds the title and its controls, over an area chart
// with the crosshatch pattern), wired to the account's balance history: one series in the accent, the range toggle in the header.
import { useMemo, useRef, useState } from "react"
import { useReducedMotion } from "motion/react"
import { ChartLineIcon } from "@/components/icons/ChartLineIcon"
import { Area, AreaChart, CartesianGrid, XAxis, YAxis } from "recharts"
import type { HistoryRange } from "../../../../shared/contract"
import { Frame, FrameDescription, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { RegionError } from "@/components/region-error"
import { SlidingToggle } from "@/components/sliding-toggle"
import { Button } from "@/components/ui/button"
import { ChartContainer, ChartTooltip, ChartTooltipContent } from "@/components/ui/chart"
import { Empty, EmptyContent, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { Skeleton } from "@/components/ui/skeleton"
import { monthDay, timeOfDay } from "@/lib/format"
import { useResult } from "@/lib/use-result"
import { balanceAxis } from "../balance-axis"
import { CHART_CONFIG, DEFAULT_RANGE, RANGES } from "./data"
import { formatSignedPercent, formatSignedUsd, formatUsd, formatWeekday } from "./format"
import { type BalanceRow, balanceRows, rangeStats } from "./range-view"

/** The block's hatch, in the accent: two strokes across an 8 px cell. */
function CrosshatchPattern() {
  return (
    <pattern id="dashboard-8-crosshatch-balance" x="0" y="0" width="8" height="8" patternUnits="userSpaceOnUse">
      <path d="M0,8 L8,0" stroke={CHART_CONFIG.balance.color} strokeWidth="0.8" opacity="0.45" />
      <path d="M0,0 L8,8" stroke={CHART_CONFIG.balance.color} strokeWidth="0.8" opacity="0.22" />
    </pattern>
  )
}

export function BalancePanel({
  accountId,
  version,
  onRefresh,
}: {
  accountId: string
  /** Changes when the page was told to read again. */
  version: number
  onRefresh: () => void
}) {
  const [selected, setSelected] = useState<HistoryRange>(DEFAULT_RANGE)
  const reduced = useReducedMotion()

  // The reply carries its own range: a change of range renders once with the old reply still in hand.
  const history = useResult(
    async () => {
      const result = await window.copytrading.read.getEquityHistory({ account_id: accountId, range: selected })
      return result.ok ? { ok: true as const, value: { range: selected, history: result.value } } : result
    },
    `${accountId}:${selected}:${version}`,
    60_000,
  )
  const data = history.status === "ready" ? history.data : null
  // Stable between the page's own re-renders: new rows would redraw the line.
  const read = useMemo(() => (data?.history ? { range: data.range, rows: balanceRows(data.history.points.map((p) => ({ at: p.at, equity: Number(p.equity) }))) } : null), [data])
  // A new range keeps drawing the last one, with its own axis labels, until its points land, so the line morphs instead of being redrawn.
  const last = useRef(read)
  if (read) last.current = read
  const pending = history.status === "loading" || (data !== null && data.range !== selected)
  const shown = pending ? last.current : read
  const rows: BalanceRow[] = shown?.rows ?? []
  const switching = pending && shown !== null
  const stats = rows.length >= 2 ? rangeStats(rows) : null
  const range = RANGES.find((r) => r.value === (shown?.range ?? selected))!
  const axis = useMemo(() => (rows.length >= 2 ? balanceAxis(rows.map((r) => r.balance)) : null), [rows])
  const tick = (key: string) => (shown?.range === "day" ? timeOfDay(key) : monthDay(key))

  return (
    <Frame className="h-full min-w-0">
      <FrameHeader className="flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex flex-col gap-px">
          <FrameTitle>Balance</FrameTitle>
          <FrameDescription className="tabular-nums">{stats ? `${formatSignedUsd(stats.change)} (${formatSignedPercent(stats.changeRatio)}) ${range.name}` : "Account equity"}</FrameDescription>
        </div>
        <SlidingToggle label="Range" value={selected} onValueChange={setSelected} options={RANGES.map((r) => ({ value: r.value, label: r.label }))} />
      </FrameHeader>
      <FramePanel className="flex flex-1 flex-col gap-4">
        {pending && !switching && <Skeleton className="h-80 w-full" role="status" aria-label="Loading balance history" />}
        {history.status === "error" && <RegionError title="Balance history did not load" message={history.error} onRetry={history.retry} />}
        {!pending && history.status === "ready" && rows.length < 2 && (
          <Empty className="h-80">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ChartLineIcon />
              </EmptyMedia>
              <EmptyTitle>No balance history for this range</EmptyTitle>
            </EmptyHeader>
            <EmptyContent>
              <Button type="button" size="sm" variant="outline" onClick={() => (selected === DEFAULT_RANGE ? onRefresh() : setSelected(DEFAULT_RANGE))}>
                {selected === DEFAULT_RANGE ? "Retry" : "Show 1 month"}
              </Button>
            </EmptyContent>
          </Empty>
        )}
        {stats && axis && (!pending || switching) && history.status !== "error" && (
          <ChartContainer
            config={CHART_CONFIG}
            className="aspect-auto! min-h-80 w-full min-w-0 flex-1"
            role="img"
            aria-label={`Balance ${range.name}, from ${formatUsd(stats.open)} to ${formatUsd(stats.close)}.`}
          >
            <AreaChart accessibilityLayer data={rows} margin={{ top: 20, right: 0, bottom: 0, left: 0 }}>
              <defs>
                <CrosshatchPattern />
              </defs>
              <CartesianGrid vertical={false} strokeDasharray="3 3" />
              <XAxis dataKey="key" tickLine={false} axisLine={false} tickMargin={8} minTickGap={32} tickFormatter={tick} />
              <YAxis hide domain={axis.domain} />
              <ChartTooltip
                content={
                  <ChartTooltipContent
                    indicator="dot"
                    className="min-w-40 gap-2.5"
                    labelFormatter={(_, payload) => {
                      const row = payload?.[0]?.payload as BalanceRow | undefined
                      return (
                        <div className="border-border/50 mb-0.5 border-b pb-2">
                          <span className="text-xs font-medium">{row ? formatWeekday(row.time) : ""}</span>
                        </div>
                      )
                    }}
                    formatter={(value, _name, item) => {
                      const row = item.payload as BalanceRow
                      return (
                        <div className="flex w-full flex-col gap-1.5">
                          <div className="flex w-full items-center justify-between gap-2">
                            <div className="flex items-center gap-1.5">
                              <span aria-hidden className="size-2.5 shrink-0 rounded-full" style={{ backgroundColor: CHART_CONFIG.balance.color }} />
                              <span className="text-muted-foreground">Balance</span>
                            </div>
                            <span className="text-foreground font-semibold tabular-nums">{formatUsd(Number(value))}</span>
                          </div>
                          <div className="text-muted-foreground flex w-full items-center justify-between gap-2 tabular-nums">
                            <span>Since the start</span>
                            <span>{`${formatSignedUsd(row.sinceStart)} (${formatSignedPercent(row.sinceStartRatio)})`}</span>
                          </div>
                        </div>
                      )
                    }}
                  />
                }
              />
              <Area
                type="monotone"
                dataKey="balance"
                fill="url(#dashboard-8-crosshatch-balance)"
                fillOpacity={0.5}
                stroke="var(--color-balance)"
                strokeWidth={1}
                dot={false}
                isAnimationActive={!reduced}
                animationDuration={400}
              />
            </AreaChart>
          </ChartContainer>
        )}
      </FramePanel>
    </Frame>
  )
}
