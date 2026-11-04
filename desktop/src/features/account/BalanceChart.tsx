import { useState } from "react"
import { ArrowDownIcon, ArrowUpIcon, ChartLineIcon } from "lucide-react"
import { CartesianGrid, Line, LineChart, ReferenceDot, XAxis, YAxis } from "recharts"
import type { AccountOverview, HistoryRange } from "../../../shared/contract"
import { Meta } from "@/components/meta"
import { Badge } from "@/components/reui/badge"
import { Frame, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { type ChartConfig, ChartContainer, ChartTooltip, ChartTooltipContent } from "@/components/ui/chart"
import { Empty, EmptyContent, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { Skeleton } from "@/components/ui/skeleton"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { money, monthDay, signedMoney, signedPercent, timeOfDay } from "@/lib/format"
import { useResult } from "@/lib/use-result"
import { dayChange } from "./model"

const RANGES: { value: HistoryRange; label: string }[] = [
  { value: "day", label: "1D" },
  { value: "week", label: "1W" },
  { value: "month", label: "1M" },
  { value: "three_months", label: "3M" },
  { value: "year", label: "1Y" },
]

/** A marker's caption, anchored away from the nearer edge so it never runs off the plot or onto the value axis. */
const markLabel = (text: string, leftHalf: boolean, dy: number, beside = false) =>
  function MarkLabel({ viewBox }: { viewBox?: { x?: number; y?: number } }) {
    const reach = beside ? 10 : 4
    return (
      <text x={(viewBox?.x ?? 0) + (leftHalf ? reach : -reach)} y={(viewBox?.y ?? 0) + dy} textAnchor={leftHalf ? "start" : "end"} fill="var(--muted-foreground)" fontSize={12}>
        {text}
      </text>
    )
  }

/**
 * The account's balance as the panel's one focal point (the ReUI chart-4 composition: the figure and its change above
 * a line with its high and low marked, the range beside the title), then today's change against yesterday's close.
 */
export function BalanceChart({ account }: { account: AccountOverview }) {
  const accountId = account.account_id
  const [range, setRange] = useState<HistoryRange>("month")
  const history = useResult(() => window.copytrading.read.getEquityHistory({ account_id: accountId, range }), `${accountId}:${range}`)
  const balance = account.balance
  const today = dayChange(account)

  const points = history.status === "ready" && history.data ? history.data.points.map((p) => ({ at: p.at, equity: Number(p.equity) })) : []
  const first = points[0]?.equity ?? 0
  const last = points.at(-1)?.equity ?? 0
  const up = last >= first
  const high = points.reduce((best, p) => (p.equity > best.equity ? p : best), points[0] ?? { at: "", equity: 0 })
  const low = points.reduce((best, p) => (p.equity < best.equity ? p : best), points[0] ?? { at: "", equity: 0 })
  const chartConfig = { equity: { label: "Balance", color: up ? "var(--success)" : "var(--destructive)" } } satisfies ChartConfig
  const tick = (at: string) => (range === "day" ? timeOfDay(at) : monthDay(at))
  const rangeLabel = RANGES.find((r) => r.value === range)?.label

  return (
    <Frame spacing="sm">
      <FrameHeader className="flex-row items-center justify-between">
        <FrameTitle>Balance</FrameTitle>
        <ToggleGroup
          value={[range]}
          onValueChange={(next) => next[0] && setRange(next[0] as HistoryRange)}
          variant="outline"
          size="sm"
          spacing={0}
          aria-label="Balance range"
        >
          {RANGES.map((r) => (
            <ToggleGroupItem key={r.value} value={r.value}>
              {r.label}
            </ToggleGroupItem>
          ))}
        </ToggleGroup>
      </FrameHeader>
      <FramePanel className="flex flex-col gap-4">
        <div className="flex flex-col gap-1.5">
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
            <span className="text-3xl font-semibold tracking-tight tabular-nums">{balance ? money(balance.equity) : "—"}</span>
            {points.length > 1 && (
              <Badge variant={up ? "success-light" : "destructive-light"}>
                {up ? <ArrowUpIcon aria-hidden="true" /> : <ArrowDownIcon aria-hidden="true" />}
                {signedPercent(first > 0 ? (last - first) / first : 0, 2)}
              </Badge>
            )}
            {points.length > 1 && <span className="text-muted-foreground text-xs tabular-nums">{`${signedMoney(last - first)} over ${rangeLabel}`}</span>}
          </div>
          {balance && today ? (
            <Meta className="text-muted-foreground text-xs tabular-nums" items={[`${signedMoney(today.amount)} today`, `closed ${money(balance.previous_close_equity)}`]} />
          ) : (
            !balance && <span className="text-muted-foreground text-xs">Not read from the broker yet</span>
          )}
        </div>
        {history.status === "loading" && <Skeleton className="h-[240px] w-full" role="status" aria-label="Loading balance history" />}
        {history.status === "error" && <RegionError title="Balance history did not load" message={history.error} onRetry={history.retry} />}
        {history.status === "ready" && points.length < 2 && (
          <Empty className="h-[240px]">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ChartLineIcon />
              </EmptyMedia>
              <EmptyTitle>No balance history for this range</EmptyTitle>
            </EmptyHeader>
            <EmptyContent>
              <Button type="button" size="sm" variant="outline" onClick={() => (range === "month" ? history.retry() : setRange("month"))}>
                {range === "month" ? "Retry" : "Show 1 month"}
              </Button>
            </EmptyContent>
          </Empty>
        )}
        {history.status === "ready" && points.length >= 2 && (
          <ChartContainer config={chartConfig} className="aspect-auto h-[240px] w-full">
            <LineChart accessibilityLayer data={points} margin={{ top: 24, right: 8, bottom: 0, left: 8 }}>
              <CartesianGrid vertical={false} />
              <XAxis dataKey="at" tickFormatter={tick} tickLine={false} axisLine={false} tickMargin={8} minTickGap={40} />
              <YAxis
                orientation="right"
                domain={["auto", "auto"]}
                tickFormatter={(v: number) => `$${Math.round(v).toLocaleString("en-US")}`}
                tickLine={false}
                axisLine={false}
                width={64}
              />
              <ChartTooltip
                cursor={false}
                content={
                  <ChartTooltipContent
                    indicator="dot"
                    labelFormatter={(_, payload) => String(payload[0] ? tick(payload[0].payload.at) : "")}
                    formatter={(value) => <span className="text-foreground font-semibold tabular-nums">{money(value as number)}</span>}
                  />
                }
              />
              <Line dataKey="equity" type="monotone" stroke="var(--color-equity)" strokeWidth={2} dot={false} activeDot={{ r: 4 }} />
              {high.equity !== low.equity && (
                <>
                  <ReferenceDot
                    x={high.at}
                    y={high.equity}
                    r={3}
                    fill="var(--background)"
                    stroke="var(--color-equity)"
                    strokeWidth={2}
                    ifOverflow="visible"
                    label={markLabel(`High ${money(high.equity)}`, points.indexOf(high) < points.length / 2, -10)}
                  />
                  <ReferenceDot
                    x={low.at}
                    y={low.equity}
                    r={3}
                    fill="var(--background)"
                    stroke="var(--color-equity)"
                    strokeWidth={2}
                    ifOverflow="visible"
                    label={markLabel(`Low ${money(low.equity)}`, points.indexOf(low) < points.length / 2, 4, true)}
                  />
                </>
              )}
            </LineChart>
          </ChartContainer>
        )}
      </FramePanel>
    </Frame>
  )
}
