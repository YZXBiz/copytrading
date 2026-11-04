// ReUI's Order Metrics (chart-25) sparkline, installed as shipped (MetricSparkline: a line over a faded grid, no tooltip)
// and wired to a held stock's five-minute bars. Changed from the block: its data and colors come from the bars, and the
// y-axis fits the bars (the block's fixed ±4 padding would flatten a price that moves by cents).
import { Line, LineChart, XAxis, YAxis } from "recharts"
import type { Bar } from "../../../shared/contract"
import { type ChartConfig, ChartContainer } from "@/components/ui/chart"
import { parseDec } from "./decimal"

/** The day's direction: the session's last close against its first open. Null when there is nothing to compare. */
export function dayDirection(bars: Bar[]): "up" | "down" | null {
  const first = bars[0] && parseDec(bars[0].open) !== null ? Number(bars[0].open) : null
  const last = bars.length > 0 && parseDec(bars[bars.length - 1]!.close) !== null ? Number(bars[bars.length - 1]!.close) : null
  if (first === null || last === null) return null
  return last >= first ? "up" : "down"
}

/** A 1-day line for a held stock, in the gain color or the loss color; nothing at all when it has no bars. */
export function PositionSparkline({ symbol, bars }: { symbol: string; bars: Bar[] | undefined }) {
  const direction = bars && bars.length >= 2 ? dayDirection(bars) : null
  if (!bars || direction === null) return null
  const chartConfig = {
    value: {
      label: symbol,
      color: direction === "up" ? "var(--success)" : "var(--destructive)",
    },
  } satisfies ChartConfig
  const data = bars.map((bar) => ({ period: bar.at, value: Number(bar.close) }))

  return (
    <div className="relative hidden h-8 w-16 shrink-0 @sm:block">
      <span
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 [background-image:linear-gradient(to_right,var(--color-border)_1px,transparent_1px),linear-gradient(to_bottom,var(--color-border)_1px,transparent_1px)] [mask-image:linear-gradient(to_right,transparent,black_14%,black_86%,transparent)] [background-size:12px_12px] opacity-30"
      />
      <ChartContainer config={chartConfig} className="relative z-10 aspect-auto! h-8 w-full" initialDimension={{ width: 64, height: 32 }}>
        <LineChart accessibilityLayer data={data} margin={{ top: 4, right: 0, bottom: 4, left: 0 }}>
          <XAxis dataKey="period" hide />
          <YAxis hide domain={["dataMin", "dataMax"]} />
          <Line dataKey="value" dot={false} isAnimationActive={false} stroke="var(--color-value)" strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.25} type="linear" />
        </LineChart>
      </ChartContainer>
    </div>
  )
}
