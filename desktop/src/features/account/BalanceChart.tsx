import { useState } from "react"
import { ArrowDownIcon, ArrowUpIcon, ChartAreaIcon } from "lucide-react"
import { Area, AreaChart, CartesianGrid, XAxis, YAxis } from "recharts"
import type { HistoryRange } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Frame, FrameDescription, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { type ChartConfig, ChartContainer, ChartTooltip, ChartTooltipContent } from "@/components/ui/chart"
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { Skeleton } from "@/components/ui/skeleton"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { money, monthDay, signedMoney, signedPercent, timeOfDay } from "@/lib/format"
import { useResult } from "@/lib/use-result"

const RANGES: { value: HistoryRange; label: string }[] = [
  { value: "day", label: "1D" },
  { value: "week", label: "1W" },
  { value: "month", label: "1M" },
  { value: "three_months", label: "3M" },
  { value: "year", label: "1Y" },
]


export function BalanceChart({ accountId }: { accountId: string }) {
  const [range, setRange] = useState<HistoryRange>("month")
  const history = useResult(() => window.copytrading.read.getEquityHistory({ account_id: accountId, range }), `${accountId}:${range}`)

  const points =
    history.status === "ready" && history.data
      ? history.data.points.map((p) => ({ at: p.at, equity: Number(p.equity) }))
      : []
  const first = points[0]?.equity ?? 0
  const last = points.at(-1)?.equity ?? 0
  const up = last >= first
  const chartConfig = { equity: { label: "Balance", color: up ? "var(--success)" : "var(--destructive)" } } satisfies ChartConfig
  const tick = (at: string) => (range === "day" ? timeOfDay(at) : monthDay(at))

  return (
    <Frame spacing="sm">
      <FrameHeader className="flex-row items-center justify-between">
        <div className="flex flex-col gap-0.5">
          <FrameTitle className="flex items-center gap-2">
            Balance
            {points.length > 1 && (
              <Badge variant={up ? "success-light" : "destructive-light"}>
                {up ? <ArrowUpIcon aria-hidden="true" /> : <ArrowDownIcon aria-hidden="true" />}
                {signedPercent(first > 0 ? (last - first) / first : 0, 2)}
              </Badge>
            )}
          </FrameTitle>
          <FrameDescription className="tabular-nums">
            {points.length > 1 ? `${money(last)} · ${signedMoney(last - first)} over ${RANGES.find((r) => r.value === range)?.label}` : "Broker equity over time"}
          </FrameDescription>
        </div>
        <ToggleGroup
          value={[range]}
          onValueChange={(next) => next[0] && setRange(next[0] as HistoryRange)}
          variant="outline"
          size="sm"
          aria-label="Balance range"
        >
          {RANGES.map((r) => (
            <ToggleGroupItem key={r.value} value={r.value}>
              {r.label}
            </ToggleGroupItem>
          ))}
        </ToggleGroup>
      </FrameHeader>
      <FramePanel>
        {history.status === "loading" && <Skeleton className="h-[240px] w-full" role="status" aria-label="Loading balance history" />}
        {history.status === "error" && (
          <RegionError title="Balance history did not load" message={history.error} onRetry={history.retry} />
        )}
        {history.status === "ready" && points.length < 2 && (
          <Empty className="h-[240px]">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ChartAreaIcon />
              </EmptyMedia>
              <EmptyTitle>No balance history for this range</EmptyTitle>
              <EmptyDescription>The broker has no equity points to draw yet.</EmptyDescription>
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
            <AreaChart accessibilityLayer data={points} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
              <defs>
                <linearGradient id="balance-gradient" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="var(--color-equity)" stopOpacity={0.5} />
                  <stop offset="95%" stopColor="var(--color-equity)" stopOpacity={0.05} />
                </linearGradient>
              </defs>
              <CartesianGrid vertical={false} strokeDasharray="3 3" />
              <XAxis dataKey="at" tickFormatter={tick} tickLine={false} axisLine={false} tickMargin={8} minTickGap={40} />
              <YAxis
                domain={["auto", "auto"]}
                tickFormatter={(v: number) => `$${Math.round(v).toLocaleString("en-US")}`}
                tickLine={false}
                axisLine={false}
                width={60}
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
              <Area dataKey="equity" type="natural" fill="url(#balance-gradient)" stroke="var(--color-equity)" strokeWidth={2} />
            </AreaChart>
          </ChartContainer>
        )}
      </FramePanel>
    </Frame>
  )
}
