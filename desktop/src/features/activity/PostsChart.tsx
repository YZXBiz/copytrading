import { Area, AreaChart, CartesianGrid, XAxis } from "recharts"
import { Frame, FrameDescription, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { ChartContainer, ChartTooltip, ChartTooltipContent } from "@/components/ui/chart"
import { ChartLegend } from "./ChartLegend"
import { OUTCOME_CONFIG } from "./chart-config"
import { BUCKETS, type DayRow } from "./post-bucket"

/** dashboard-7's crosshatch under each area, one colour per outcome. */
function CrosshatchPattern() {
  return (
    <>
      {BUCKETS.map((bucket) => (
        <pattern key={bucket} id={`activity-posts-${bucket}`} x="0" y="0" width="8" height="8" patternUnits="userSpaceOnUse">
          <path d="M0,8 L8,0" stroke={OUTCOME_CONFIG[bucket].color} strokeOpacity={0.42} strokeWidth={0.9} />
          <path d="M0,0 L8,8" stroke={OUTCOME_CONFIG[bucket].color} strokeOpacity={0.22} strokeWidth={0.9} />
        </pattern>
      ))}
    </>
  )
}

const sum = (rows: DayRow[], ...keys: (typeof BUCKETS)[number][]) => rows.reduce((n, row) => n + keys.reduce((m, key) => m + row[key], 0), 0)

/** dashboard-7's Revenue Pace chart: posts per day over the last 30 days, stacked by how each ended. */
export function PostsChart({ rows }: { rows: DayRow[] }) {
  const posts = sum(rows, ...BUCKETS)
  const traded = sum(rows, "traded")
  return (
    <Frame className="flex h-full min-w-0 flex-col">
      <FrameHeader className="flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex flex-col gap-px">
          <FrameTitle>Posts per day</FrameTitle>
          <FrameDescription>Last 30 days, by how each ended</FrameDescription>
        </div>
        <ChartLegend />
      </FrameHeader>
      <FramePanel className="flex min-h-[360px] flex-1 flex-col gap-4">
        <div className="grid gap-3 sm:grid-cols-3">
          <div className="min-w-0">
            <div className="text-muted-foreground text-xs">Posts</div>
            <div className="text-lg font-semibold tabular-nums">{posts}</div>
          </div>
          <div className="min-w-0">
            <div className="text-muted-foreground text-xs">Traded</div>
            <div className="flex items-baseline gap-1.5">
              <span className="text-lg font-semibold tabular-nums">{traded}</span>
              {posts > 0 && <span className="text-muted-foreground text-xs font-medium tabular-nums">{Math.round((traded / posts) * 100)}%</span>}
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-muted-foreground text-xs">Skipped</div>
            <div className="text-lg font-semibold tabular-nums">{sum(rows, "skipped")}</div>
          </div>
        </div>
        <ChartContainer config={OUTCOME_CONFIG} className="mt-auto h-64 w-full min-w-0">
          <AreaChart accessibilityLayer data={rows} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
            <defs>
              <CrosshatchPattern />
            </defs>
            <CartesianGrid vertical={false} strokeDasharray="3 3" />
            <XAxis dataKey="label" tickLine={false} axisLine={false} tickMargin={10} minTickGap={28} />
            <ChartTooltip cursor={false} content={<ChartTooltipContent indicator="dot" className="min-w-44 gap-2.5" />} />
            {BUCKETS.map((bucket) => (
              <Area key={bucket} dataKey={bucket} type="monotone" stackId="posts" fill={`url(#activity-posts-${bucket})`} fillOpacity={0.65} stroke={`var(--color-${bucket})`} strokeWidth={2} />
            ))}
          </AreaChart>
        </ChartContainer>
      </FramePanel>
    </Frame>
  )
}
