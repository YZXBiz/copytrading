"use client"

import {
  memo,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
  type ReactElement,
  type ReactNode,
} from "react"
import { Badge } from "@/components/reui/badge"
import { RollingNumber } from "@/components/rolling-number"
import { cn } from "cn"
import {
  CartesianGrid,
  Curve,
  DefaultZIndexes,
  Line,
  LineChart,
  usePlotArea,
  XAxis,
  YAxis,
  ZIndexLayer,
  type CurveProps,
  type LineProps,
  type TooltipContentProps,
} from "recharts"

import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart"

import { balanceAxis } from "../balance-axis"
import { CHART_CONFIG } from "./data"
import {
  PERCENT_SIGNED_OPTIONS,
  USD_OPTIONS,
  USD_SIGNED_OPTIONS,
  formatAxis,
  formatDay,
  formatUsd,
  formatWeekday,
} from "./format"
import { ROW_ICONS } from "./icons"
import { type BalanceRow } from "./range-view"
import { CAP_BOX, SeriesKeyMark } from "./value-faces"

/** The house ease-out, which Recharts parses at runtime; its own "ease-out"
 *  keyword is the slow-starting (0.42, 0, 0.58, 1). */
const EASE_OUT: string = "cubic-bezier(0.23, 1, 0.32, 1)"

/** Every series moves to new data in one rhythm: Recharts interpolates
 *  each point from the last layout, so a range switch morphs the line. */
const SERIES_MOTION = {
  animationDuration: 400,
  animationEasing: EASE_OUT as LineProps["animationEasing"],
  animationBegin: 0,
} as const

/** The first draw is taken as landed this long after its duration. */
const SETTLE_MARGIN_MS = 60

const MARGIN = { top: 28, right: 4, bottom: 0, left: 4 }
const AXIS_WIDTH = 52
/** Close to the plot's real size, so the first draw measures the line at
 *  the length it settles at. */
const INITIAL_SIZE = { width: 820, height: 288 }
/** Hover is instant: the cursor and the active dot never transition. */
const CURSOR = {
  stroke: "var(--border)",
  strokeWidth: 1,
  strokeDasharray: "3 3",
}
const ACTIVE_DOT = {
  r: 4,
  fill: "var(--color-balance)",
  stroke: "var(--card)",
  strokeWidth: 2,
}

/** A layer toggle fades both ways and can reverse mid-fade: a transition on
 *  a line that stays mounted, never a remount and a fresh draw. */
const LAYER_FADE =
  "transition-opacity duration-200 ease-[cubic-bezier(0.23,1,0.32,1)]"
/** Marks wait for the first draw to land, then fade in on it. */
const MARK_REVEAL = `${LAYER_FADE} group-data-[intro=drawing]/c4:opacity-0`

const REDUCED_MOTION = "(prefers-reduced-motion: reduce)"

function subscribeMotion(onChange: () => void) {
  const query = window.matchMedia(REDUCED_MOTION)
  query.addEventListener("change", onChange)
  return () => query.removeEventListener("change", onChange)
}

function useReducedMotion() {
  return useSyncExternalStore(
    subscribeMotion,
    () => window.matchMedia(REDUCED_MOTION).matches,
    () => false
  )
}

type CurvePoints = NonNullable<CurveProps["points"]>

/** After the first draw a line keeps its own dash, or a longer range would
 *  regrow it from the old length and end it short of today for a moment. */
function curveFor(
  settled: boolean,
  dash?: string,
  marks?: (points: CurvePoints) => ReactNode
) {
  return function lineCurve(props: CurveProps): ReactElement {
    return (
      <>
        <Curve
          {...props}
          strokeDasharray={settled ? dash : props.strokeDasharray}
        />
        {/* Marks read the frame's own points: one render per frame, where
            a per-close `dot` callback renders every close each frame. */}
        {marks && props.points ? marks(props.points) : null}
      </>
    )
  }
}

/** A label clear of the plot's edges: left-aligned near the first close,
 *  right-aligned near the last. */
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
      <circle
        cx={cx}
        cy={cy}
        r={7}
        fill="var(--color-balance)"
        fillOpacity={0.16}
      />
      <circle
        cx={cx}
        cy={cy}
        r={3.5}
        fill="var(--color-balance)"
        stroke="var(--card)"
        strokeWidth={1.5}
      />
    </g>
  )
}

/** The space a marker label's line takes beside its dot. */
const LABEL_ROOM = 22

/** "High $26,352.07" above its dot, or "Low" below; flipped to the other
 *  side when the plot's edge leaves no room. */
function MarkerLabel({
  x,
  y,
  high,
  anchor,
  value,
}: {
  x: number
  y: number
  high: boolean
  anchor: "start" | "middle" | "end"
  value: number
}) {
  const plot = usePlotArea()
  const roomAbove = !plot || y - LABEL_ROOM >= plot.y
  const roomBelow = !plot || y + LABEL_ROOM <= plot.y + plot.height
  const above = high ? roomAbove || !roomBelow : !roomBelow && roomAbove
  return (
    <text
      x={x}
      y={above ? y - 12 : y + 20}
      textAnchor={anchor}
      stroke="var(--card)"
      strokeWidth={3}
      strokeLinejoin="round"
      paintOrder="stroke"
      className="text-xs tabular-nums"
    >
      <tspan className="fill-muted-foreground">{high ? "High " : "Low "}</tspan>
      <tspan className="fill-foreground font-medium">{formatUsd(value)}</tspan>
    </text>
  )
}

/** Hidden with the High and Low layer, fading like the other layers. */
const MARKER_LAYER = "group-data-[markers=off]/c4:opacity-0"

/** A point Recharts placed this frame, or null across a gap. */
function placed(points: CurvePoints, index: number) {
  const point = points[index]
  return point?.x == null || point.y == null ? null : { x: point.x, y: point.y }
}

/** Today's close, and the range's high above its dot and low below it, in
 *  the dots' layer over every line. `rows[i]` is plotted at `points[i]`. */
function BalanceMarks({
  points,
  rows,
}: {
  points: CurvePoints
  rows: BalanceRow[]
}) {
  const today = points.length - 1
  const end = placed(points, today)
  return (
    <ZIndexLayer zIndex={DefaultZIndexes.scatter}>
      {end ? <TodayMark cx={end.x} cy={end.y} /> : null}
      {rows.flatMap((row, index) => {
        const point = row.marker ? placed(points, index) : null
        if (!row.marker || !point) return []
        return (
          <g key={row.marker} className={cn(MARK_REVEAL, MARKER_LAYER)}>
            {index === today ? null : (
              <circle
                cx={point.x}
                cy={point.y}
                r={3.5}
                fill="var(--card)"
                stroke="var(--color-balance)"
                strokeWidth={2}
              />
            )}
            <MarkerLabel
              x={point.x}
              y={point.y}
              high={row.marker === "high"}
              anchor={anchorOf(point.x, points)}
              value={row.balance}
            />
          </g>
        )
      })}
    </ZIndexLayer>
  )
}

/** The average's label at the line's left end, over every line. */
function AverageMark({
  points,
  value,
}: {
  points: CurvePoints
  value: number
}) {
  const start = placed(points, 0)
  if (!start) return null
  return (
    <ZIndexLayer zIndex={DefaultZIndexes.scatter}>
      <text
        aria-hidden="true"
        x={start.x + 4}
        y={start.y + 16}
        stroke="var(--card)"
        strokeWidth={3}
        strokeLinejoin="round"
        paintOrder="stroke"
        className={cn(
          "fill-muted-foreground text-xs tabular-nums",
          MARK_REVEAL,
          "group-data-[average=off]/c4:opacity-0"
        )}
      >
        {`Avg ${formatAxis(value)}`}
      </text>
    </ZIndexLayer>
  )
}

/** A signed amount and its percentage, toned by direction. */
function Change({ value, ratio }: { value: number; ratio: number }) {
  return (
    <span className="flex items-center gap-1.5 tabular-nums">
      <span
        className={cn(
          CAP_BOX,
          "font-medium",
          value >= 0 ? "text-success" : "text-destructive"
        )}
      >
        <RollingNumber value={value} format={USD_SIGNED_OPTIONS} quick />
      </span>
      <span className={cn(CAP_BOX, "text-muted-foreground")}>
        <RollingNumber value={ratio} format={PERCENT_SIGNED_OPTIONS} quick />
      </span>
    </span>
  )
}

/** A tooltip row: a 16px glyph slot, the label, then the reading. */
function CardRow({
  glyph,
  label,
  children,
}: {
  glyph: ReactNode
  label: string
  children: ReactNode
}) {
  return (
    <div className="flex h-4 items-center justify-between gap-6">
      <span className="text-muted-foreground inline-flex items-center gap-1.5">
        <span className="flex size-4 shrink-0 items-center justify-center">
          {glyph}
        </span>
        <span className={CAP_BOX}>{label}</span>
      </span>
      {children}
    </div>
  )
}

/** One close, read in full: the balance and its move since the range opened. */
function BalanceCard({
  opened,
  active,
  payload,
}: { opened: number } & Partial<
  Pick<TooltipContentProps, "active" | "payload">
>) {
  const row: BalanceRow | undefined = payload?.[0]?.payload
  if (!active || !row || !payload) return null
  return (
    <ChartTooltipContent
      active
      payload={payload.slice(0, 1)}
      className="w-auto min-w-60"
      labelFormatter={() => (
        <span className="flex h-5 items-center justify-between gap-3">
          <span className={CAP_BOX}>{formatWeekday(row.time)}</span>
          {row.marker ? (
            <Badge variant="outline">
              {row.marker === "high" ? "High" : "Low"}
            </Badge>
          ) : null}
        </span>
      )}
      formatter={() => (
        <div className="flex flex-1 flex-col gap-1.5">
          <CardRow glyph={<SeriesKeyMark series="balance" />} label="Balance">
            <span className={cn(CAP_BOX, "font-medium tabular-nums")}>
              <RollingNumber value={row.balance} format={USD_OPTIONS} quick />
            </span>
          </CardRow>
          <CardRow glyph={ROW_ICONS.since} label={`Since ${formatDay(opened)}`}>
            <Change value={row.sinceStart} ratio={row.sinceStartRatio} />
          </CardRow>
        </div>
      )}
    />
  )
}

/** Memoised: the page re-renders on its own refreshes, never the chart. */
export const BalancePlot = memo(function BalancePlot({
  rows,
  tick,
  markers,
  average,
  label,
}: {
  rows: BalanceRow[]
  /** A close's key as the axis says it: a clock time on a day, a date otherwise. */
  tick: (key: string) => string
  markers: boolean
  average: boolean
  label: string
}) {
  // Off only for reduced motion, which draws at rest.
  const reduced = useReducedMotion()
  const motion = !reduced
  const [drawn, setDrawn] = useState(false)
  const settled = drawn || !motion
  // Recharts calls `onAnimationEnd` on every effect cleanup too, so the
  // first draw counts as landed one duration after its last start.
  const settleTimer = useRef<number | null>(null)
  const onDrawStart = useCallback(() => {
    if (settleTimer.current !== null) window.clearTimeout(settleTimer.current)
    settleTimer.current = window.setTimeout(
      () => setDrawn(true),
      SERIES_MOTION.animationDuration + SETTLE_MARGIN_MS
    )
  }, [])
  useEffect(
    () => () => {
      if (settleTimer.current !== null) window.clearTimeout(settleTimer.current)
    },
    []
  )
  const shapes = useMemo(
    () => ({
      balance: curveFor(settled, undefined, (points) => (
        <BalanceMarks points={points} rows={rows} />
      )),
      average: curveFor(settled, "4 4", (points) => (
        <AverageMark points={points} value={rows[0].average} />
      )),
    }),
    [settled, rows]
  )
  const axis = useMemo(() => balanceAxis(rows.map((row) => row.balance)), [rows])
  const axisMoney = (value: number) =>
    `$${value.toLocaleString("en-US", { minimumFractionDigits: axis.digits, maximumFractionDigits: axis.digits })}`

  return (
    // A click focuses Recharts' layer group; only keyboard focus rings.
    <ChartContainer
      config={CHART_CONFIG}
      role="group"
      aria-label={label}
      initialDimension={INITIAL_SIZE}
      data-intro={settled ? "done" : "drawing"}
      data-average={average ? "on" : "off"}
      data-markers={markers ? "on" : "off"}
      className="group/c4 has-[:focus-visible]:ring-ring/50 aspect-auto h-72 w-full min-w-0 has-[:focus-visible]:ring-[3px] [&_[class*=recharts-zIndex-layer]]:outline-hidden"
    >
      <LineChart accessibilityLayer data={rows} margin={MARGIN}>
        {/* Muted horizontal rules on the value ticks: the container tints
            them to the border token. */}
        <CartesianGrid vertical={false} syncWithTicks />
        <XAxis
          dataKey="key"
          tickFormatter={tick}
          interval="equidistantPreserveStart"
          minTickGap={40}
          padding={{ left: 28, right: 0 }}
          tickLine={false}
          axisLine={false}
          tickMargin={10}
        />
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
        <ChartTooltip
          cursor={CURSOR}
          isAnimationActive={false}
          content={<BalanceCard opened={rows[0].time} />}
        />
        {/* The average stays mounted under the line, so it morphs with it
            and its toggle fades instead of popping. */}
        <Line
          dataKey="average"
          type="linear"
          stroke="var(--color-average)"
          strokeOpacity={0.7}
          strokeWidth={1}
          strokeDasharray="4 4"
          dot={false}
          activeDot={false}
          shape={shapes.average}
          className={cn(LAYER_FADE, "group-data-[average=off]/c4:opacity-0")}
          {...SERIES_MOTION}
          isAnimationActive={motion}
        />
        <Line
          dataKey="balance"
          type="linear"
          stroke="var(--color-balance)"
          strokeWidth={2}
          dot={false}
          activeDot={ACTIVE_DOT}
          shape={shapes.balance}
          onAnimationStart={onDrawStart}
          {...SERIES_MOTION}
          isAnimationActive={motion}
        />
      </LineChart>
    </ChartContainer>
  )
})
