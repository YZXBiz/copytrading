import { memo, useEffect, useMemo, useState, useSyncExternalStore, type ReactElement } from "react"
import { CartesianGrid, Curve, DefaultZIndexes, Line, LineChart, XAxis, YAxis, ZIndexLayer, usePlotArea, type CurveProps, type LineProps } from "recharts"
import { type ChartConfig, ChartContainer, ChartTooltip, ChartTooltipContent } from "@/components/ui/chart"
import { money, signedMoney, signedPercent } from "@/lib/format"
import { cn } from "@/lib/utils"
import { balanceAxis } from "./balance-axis"

export interface BalancePoint {
  at: string
  equity: number
}

/** One ease for every move: a new range morphs the line from the last one, as in ReUI's Balance Tracker. */
const MOTION = { animationDuration: 400, animationEasing: "cubic-bezier(0.23, 1, 0.32, 1)" as LineProps["animationEasing"], animationBegin: 0 }
/** The first draw has landed this long after it starts; the marks fade in then. */
const DRAW_MS = 460

const REDUCED = "(prefers-reduced-motion: reduce)"
const subscribeMotion = (onChange: () => void) => {
  const query = window.matchMedia(REDUCED)
  query.addEventListener("change", onChange)
  return () => query.removeEventListener("change", onChange)
}
const useReducedMotion = () => useSyncExternalStore(subscribeMotion, () => window.matchMedia(REDUCED).matches, () => false)

type CurvePoints = NonNullable<CurveProps["points"]>

/** The line's last close: a dot in a soft halo. */
function TodayMark({ x, y, className }: { x: number; y: number; className: string }) {
  return (
    <g className={className}>
      <circle cx={x} cy={y} r={7} fill="var(--color-balance)" fillOpacity={0.16} />
      <circle cx={x} cy={y} r={3.5} fill="var(--color-balance)" stroke="var(--card)" strokeWidth={1.5} />
    </g>
  )
}

/** "High $3,068.26" above its dot, "Low" below it, flipped when the plot's edge leaves no room; anchored away from the nearer edge. */
function MarkerLabel({ x, y, high, anchor, value }: { x: number; y: number; high: boolean; anchor: "start" | "middle" | "end"; value: number }) {
  const plot = usePlotArea()
  const roomAbove = !plot || y - 22 >= plot.y
  const roomBelow = !plot || y + 22 <= plot.y + plot.height
  const above = high ? roomAbove || !roomBelow : !roomBelow && roomAbove
  return (
    <text x={x} y={above ? y - 12 : y + 20} textAnchor={anchor} stroke="var(--card)" strokeWidth={3} strokeLinejoin="round" paintOrder="stroke" className="text-xs tabular-nums">
      <tspan className="fill-muted-foreground">{high ? "High " : "Low "}</tspan>
      <tspan className="fill-foreground font-medium">{money(value)}</tspan>
    </text>
  )
}

const REVEAL = "transition-opacity duration-200 ease-[cubic-bezier(0.22,1,0.36,1)]"

/** Today's close and the range's high and low, drawn from the frame's own points so they ride the morph. */
function Marks({ points, rows, high, low, shown }: { points: CurvePoints; rows: BalancePoint[]; high: number; low: number; shown: boolean }) {
  const first = points[0]?.x ?? 0
  const last = points.at(-1)?.x ?? 0
  const anchorOf = (x: number) => {
    const share = (x - first) / Math.max(1, last - first)
    return share < 0.12 ? "start" : share > 0.88 ? "end" : "middle"
  }
  const className = cn(REVEAL, !shown && "opacity-0")
  const end = points.at(-1)
  return (
    <ZIndexLayer zIndex={DefaultZIndexes.scatter}>
      {end?.x != null && end.y != null && <TodayMark x={end.x} y={end.y} className={className} />}
      {high !== low &&
        [high, low].map((index) => {
          const point = points[index]
          if (point?.x == null || point.y == null) return null
          return (
            <g key={index} className={className}>
              {index !== rows.length - 1 && <circle cx={point.x} cy={point.y} r={3.5} fill="var(--card)" stroke="var(--color-balance)" strokeWidth={2} />}
              <MarkerLabel x={point.x} y={point.y} high={index === high} anchor={anchorOf(point.x)} value={rows[index]!.equity} />
            </g>
          )
        })}
    </ZIndexLayer>
  )
}

/**
 * The balance line (ReUI Balance Tracker, chart-4): it morphs between ranges, marks today's close and the range's
 * high and low, and a readout follows the pointer. The benchmark, average line, colour picker and export are not here.
 */
export const BalancePlot = memo(function BalancePlot({ points, tick, up }: { points: BalancePoint[]; tick: (at: string) => string; up: boolean }) {
  const reduced = useReducedMotion()
  const [drawn, setDrawn] = useState(false)
  useEffect(() => {
    const timer = setTimeout(() => setDrawn(true), DRAW_MS)
    return () => clearTimeout(timer)
  }, [])
  const config = { balance: { label: "Balance", color: up ? "var(--success)" : "var(--destructive)" } } satisfies ChartConfig
  const axis = useMemo(() => balanceAxis(points.map((p) => p.equity)), [points])
  const high = points.reduce((best, p, i) => (p.equity > points[best]!.equity ? i : best), 0)
  const low = points.reduce((best, p, i) => (p.equity < points[best]!.equity ? i : best), 0)
  const shape = useMemo(
    () =>
      function BalanceCurve(props: CurveProps): ReactElement {
        return (
          <>
            <Curve {...props} />
            {props.points && <Marks points={props.points} rows={points} high={high} low={low} shown={drawn || reduced} />}
          </>
        )
      },
    [points, high, low, drawn, reduced],
  )
  const opened = points[0]!.equity
  const axisMoney = (value: number) => `$${value.toLocaleString("en-US", { minimumFractionDigits: axis.digits, maximumFractionDigits: axis.digits })}`
  return (
    <ChartContainer config={config} role="group" aria-label="Balance over the range" className="aspect-auto h-72 w-full min-w-0 [&_[class*=recharts-zIndex-layer]]:outline-hidden">
      <LineChart accessibilityLayer data={points} margin={{ top: 28, right: 4, bottom: 0, left: 4 }}>
        <CartesianGrid vertical={false} syncWithTicks />
        <XAxis dataKey="at" tickFormatter={tick} tickLine={false} axisLine={false} tickMargin={10} minTickGap={40} />
        <YAxis orientation="right" domain={axis.domain} ticks={axis.ticks} allowDataOverflow tickFormatter={axisMoney} tickLine={false} axisLine={false} width={axis.digits ? 72 : 64} tickMargin={6} />
        <ChartTooltip
          cursor={{ stroke: "var(--border)", strokeWidth: 1, strokeDasharray: "3 3" }}
          isAnimationActive={false}
          content={
            <ChartTooltipContent
              indicator="dot"
              labelFormatter={(_, payload) => (payload[0] ? tick(payload[0].payload.at) : "")}
              formatter={(value) => {
                const since = Number(value) - opened
                return (
                  <div className="flex flex-1 items-center justify-between gap-6 tabular-nums">
                    <span className="text-foreground font-semibold">{money(value as number)}</span>
                    <span className="text-muted-foreground">{`${signedMoney(since)} (${signedPercent(opened > 0 ? since / opened : 0, 2)})`}</span>
                  </div>
                )
              }}
            />
          }
        />
        <Line dataKey="equity" type="linear" stroke="var(--color-balance)" strokeWidth={2} dot={false} activeDot={{ r: 4, fill: "var(--color-balance)", stroke: "var(--card)", strokeWidth: 2 }} shape={shape} {...MOTION} isAnimationActive={!reduced} />
      </LineChart>
    </ChartContainer>
  )
})
