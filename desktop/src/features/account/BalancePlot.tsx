// The line of ReUI's Balance Tracker (chart-4, balance-plot.tsx), kept as shipped: the morph between ranges, the
// first-draw settle that keeps a longer range from regrowing from the old length, today's dot, the high and low
// markers and the readout card. The benchmark, average line, colour picker and demo hooks are not here. The curve
// is monotone, as this page always drew it.
import { memo, useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactElement, type ReactNode } from "react"
import { HistoryIcon } from "lucide-react"
import { CartesianGrid, Curve, DefaultZIndexes, Line, LineChart, XAxis, YAxis, ZIndexLayer, usePlotArea, type CurveProps, type LineProps } from "recharts"
import { Badge } from "@/components/reui/badge"
import { type ChartConfig, ChartContainer, ChartTooltip, ChartTooltipContent } from "@/components/ui/chart"
import { money, signedMoney, signedPercent } from "@/lib/format"
import { cn } from "@/lib/utils"
import { balanceAxis } from "./balance-axis"
import type { BalanceRow } from "./balance-rows"

/** The house ease-out, which Recharts parses at runtime; its own "ease-out" keyword is the slow-starting (0.42, 0, 0.58, 1). */
const EASE_OUT = "cubic-bezier(0.23, 1, 0.32, 1)"

/** Every series moves to new data in one rhythm: Recharts interpolates each point from the last layout, so a range switch morphs the line. */
const SERIES_MOTION = {
  animationDuration: 400,
  animationEasing: EASE_OUT as LineProps["animationEasing"],
  animationBegin: 0,
} as const

/** The first draw is taken as landed this long after its duration. */
const SETTLE_MARGIN_MS = 60

const MARGIN = { top: 28, right: 4, bottom: 0, left: 4 }
/** Close to the plot's real size, so the first draw measures the line at the length it settles at. */
const INITIAL_SIZE = { width: 820, height: 288 }
/** Hover is instant: the cursor and the active dot never transition. */
const CURSOR = { stroke: "var(--border)", strokeWidth: 1, strokeDasharray: "3 3" }
const ACTIVE_DOT = { r: 4, fill: "var(--color-balance)", stroke: "var(--card)", strokeWidth: 2 }

/** Marks wait for the first draw to land, then fade in on it. */
const MARK_REVEAL = "transition-opacity duration-200 ease-[cubic-bezier(0.23,1,0.32,1)] group-data-[intro=drawing]/bal:opacity-0"

/** Trims a label to its caps, so `items-center` lines the letters up with the glyph beside it. Needs a fixed-height row. */
const CAP_BOX = "[text-box:trim-both_cap_alphabetic]"

const REDUCED_MOTION = "(prefers-reduced-motion: reduce)"
const subscribeMotion = (onChange: () => void) => {
  const query = window.matchMedia(REDUCED_MOTION)
  query.addEventListener("change", onChange)
  return () => query.removeEventListener("change", onChange)
}
const useReducedMotion = () => useSyncExternalStore(subscribeMotion, () => window.matchMedia(REDUCED_MOTION).matches, () => false)

type CurvePoints = NonNullable<CurveProps["points"]>

/** After the first draw the line keeps no dash of its own, or a longer range would regrow it from the old length and end it short of today for a moment. */
function curveFor(settled: boolean, marks: (points: CurvePoints) => ReactNode) {
  return function lineCurve(props: CurveProps): ReactElement {
    return (
      <>
        <Curve {...props} strokeDasharray={settled ? undefined : props.strokeDasharray} />
        {/* Marks read the frame's own points: one render per frame, where a per-close `dot` callback renders every close each frame. */}
        {props.points ? marks(props.points) : null}
      </>
    )
  }
}

/** A label clear of the plot's edges: left-aligned near the first close, right-aligned near the last. */
function anchorOf(x: number, points: CurvePoints) {
  const first = points[0]?.x ?? x
  const last = points[points.length - 1]?.x ?? x
  const share = (x - first) / Math.max(1, last - first)
  return share < 0.12 ? "start" : share > 0.88 ? "end" : "middle"
}

/** Today's close: a dot in a soft halo at the line's end. */
function TodayMark({ cx, cy }: { cx: number; cy: number }) {
  return (
    <g className={MARK_REVEAL}>
      <circle cx={cx} cy={cy} r={7} fill="var(--color-balance)" fillOpacity={0.16} />
      <circle cx={cx} cy={cy} r={3.5} fill="var(--color-balance)" stroke="var(--card)" strokeWidth={1.5} />
    </g>
  )
}

/** The space a marker label's line takes beside its dot. */
const LABEL_ROOM = 22

/** "High $3,068.26" above its dot, or "Low" below; flipped to the other side when the plot's edge leaves no room. */
function MarkerLabel({ x, y, high, anchor, value }: { x: number; y: number; high: boolean; anchor: "start" | "middle" | "end"; value: number }) {
  const plot = usePlotArea()
  const roomAbove = !plot || y - LABEL_ROOM >= plot.y
  const roomBelow = !plot || y + LABEL_ROOM <= plot.y + plot.height
  const above = high ? roomAbove || !roomBelow : !roomBelow && roomAbove
  return (
    <text x={x} y={above ? y - 12 : y + 20} textAnchor={anchor} stroke="var(--card)" strokeWidth={3} strokeLinejoin="round" paintOrder="stroke" className="text-xs tabular-nums">
      <tspan className="fill-muted-foreground">{high ? "High " : "Low "}</tspan>
      <tspan className="fill-foreground font-medium">{money(value)}</tspan>
    </text>
  )
}

/** A point Recharts placed this frame, or null across a gap. */
function placed(points: CurvePoints, index: number) {
  const point = points[index]
  return point?.x == null || point.y == null ? null : { x: point.x, y: point.y }
}

/** Today's close, and the range's high above its dot and low below it, in the dots' layer over the line. `rows[i]` is plotted at `points[i]`. */
function BalanceMarks({ points, rows }: { points: CurvePoints; rows: BalanceRow[] }) {
  const today = points.length - 1
  const end = placed(points, today)
  return (
    <ZIndexLayer zIndex={DefaultZIndexes.scatter}>
      {end ? <TodayMark cx={end.x} cy={end.y} /> : null}
      {rows.flatMap((row, index) => {
        const point = row.marker ? placed(points, index) : null
        if (!row.marker || !point) return []
        return (
          <g key={row.marker} className={MARK_REVEAL}>
            {index === today ? null : <circle cx={point.x} cy={point.y} r={3.5} fill="var(--card)" stroke="var(--color-balance)" strokeWidth={2} />}
            <MarkerLabel x={point.x} y={point.y} high={row.marker === "high"} anchor={anchorOf(point.x, points)} value={row.balance} />
          </g>
        )
      })}
    </ZIndexLayer>
  )
}

/** A signed amount and its percentage, toned by direction. */
function Change({ value, ratio }: { value: number; ratio: number }) {
  return (
    <span className="flex items-center gap-1.5 tabular-nums">
      <span className={cn(CAP_BOX, "font-medium", value >= 0 ? "text-success" : "text-destructive")}>{signedMoney(value)}</span>
      <span className={cn(CAP_BOX, "text-muted-foreground")}>{signedPercent(ratio, 2)}</span>
    </span>
  )
}

/** A readout row: a 16px glyph slot, the label, then the reading. */
function CardRow({ glyph, label, children }: { glyph: ReactNode; label: string; children: ReactNode }) {
  return (
    <div className="flex h-4 items-center justify-between gap-6">
      <span className="text-muted-foreground inline-flex items-center gap-1.5">
        <span className="flex size-4 shrink-0 items-center justify-center">{glyph}</span>
        <span className={CAP_BOX}>{label}</span>
      </span>
      {children}
    </div>
  )
}

/** One close, read in full: the balance and its move since the range opened. */
function BalanceCard({ opened, tick, active, payload }: { opened: string; tick: (key: string) => string; active?: boolean; payload?: { payload: BalanceRow }[] }) {
  const row = payload?.[0]?.payload
  if (!active || !row || !payload) return null
  return (
    <ChartTooltipContent
      active
      // ChartTooltipContent reads the whole recharts payload; the card only needs the first entry.
      payload={payload.slice(0, 1) as never}
      className="w-auto min-w-60"
      labelFormatter={() => (
        <span className="flex h-5 items-center justify-between gap-3">
          <span className={CAP_BOX}>{tick(row.key)}</span>
          {row.marker ? <Badge variant="outline">{row.marker === "high" ? "High" : "Low"}</Badge> : null}
        </span>
      )}
      formatter={() => (
        <div className="flex flex-1 flex-col gap-1.5">
          <CardRow glyph={<span aria-hidden="true" className="h-0.5 w-3 rounded-full bg-(--color-balance)" />} label="Balance">
            <span className={cn(CAP_BOX, "font-medium tabular-nums")}>{money(row.balance)}</span>
          </CardRow>
          <CardRow glyph={<HistoryIcon className="size-4" aria-hidden="true" />} label={`Since ${opened}`}>
            <Change value={row.sinceStart} ratio={row.sinceStartRatio} />
          </CardRow>
        </div>
      )}
    />
  )
}

/** Memoised: the page re-renders on its own refreshes, never the chart. */
export const BalancePlot = memo(function BalancePlot({ rows, tick, up }: { rows: BalanceRow[]; tick: (key: string) => string; up: boolean }) {
  // Off only for reduced motion, which draws at rest.
  const reduced = useReducedMotion()
  const motion = !reduced
  const [drawn, setDrawn] = useState(false)
  const settled = drawn || !motion
  // Recharts calls `onAnimationEnd` on every effect cleanup too, so the first draw counts as landed one duration after its last start.
  const settleTimer = useRef<number | null>(null)
  const onDrawStart = useCallback(() => {
    if (settleTimer.current !== null) window.clearTimeout(settleTimer.current)
    settleTimer.current = window.setTimeout(() => setDrawn(true), SERIES_MOTION.animationDuration + SETTLE_MARGIN_MS)
  }, [])
  useEffect(
    () => () => {
      if (settleTimer.current !== null) window.clearTimeout(settleTimer.current)
    },
    [],
  )
  const shape = useMemo(() => curveFor(settled, (points) => <BalanceMarks points={points} rows={rows} />), [settled, rows])
  const axis = useMemo(() => balanceAxis(rows.map((r) => r.balance)), [rows])
  const config = { balance: { label: "Balance", color: up ? "var(--success)" : "var(--destructive)" } } satisfies ChartConfig
  const axisMoney = (value: number) => `$${value.toLocaleString("en-US", { minimumFractionDigits: axis.digits, maximumFractionDigits: axis.digits })}`
  return (
    // A click focuses Recharts' layer group; only keyboard focus rings.
    <ChartContainer
      config={config}
      role="group"
      aria-label="Balance over the range. Arrow keys move between points."
      initialDimension={INITIAL_SIZE}
      data-intro={settled ? "done" : "drawing"}
      className="group/bal has-[:focus-visible]:ring-ring/50 aspect-auto h-72 w-full min-w-0 has-[:focus-visible]:ring-[3px] [&_[class*=recharts-zIndex-layer]]:outline-hidden"
    >
      <LineChart accessibilityLayer data={rows} margin={MARGIN}>
        <CartesianGrid vertical={false} syncWithTicks />
        <XAxis dataKey="key" tickFormatter={tick} interval="equidistantPreserveStart" minTickGap={40} padding={{ left: 28, right: 0 }} tickLine={false} axisLine={false} tickMargin={10} />
        <YAxis
          orientation="right"
          domain={axis.domain}
          ticks={axis.ticks}
          allowDataOverflow
          tickFormatter={axisMoney}
          width={axis.digits ? 72 : 64}
          tickLine={false}
          axisLine={false}
          tickMargin={6}
        />
        <ChartTooltip cursor={CURSOR} isAnimationActive={false} content={<BalanceCard opened={tick(rows[0]!.key)} tick={tick} />} />
        <Line dataKey="balance" type="monotone" stroke="var(--color-balance)" strokeWidth={2} dot={false} activeDot={ACTIVE_DOT} shape={shape} onAnimationStart={onDrawStart} {...SERIES_MOTION} isAnimationActive={motion} />
      </LineChart>
    </ChartContainer>
  )
})
