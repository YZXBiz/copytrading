// solution-analytics-8's breakdown (MetricBreakdown), as shipped: a Frame of rows, each a name and its figure over a hatched
// progress bar. Changed from the block: the rows are the guru's best and worst call and what is still open, and the bar is
// each figure's size against the largest of them, in green or red.
import type { GuruPerformance } from "../../../shared/contract"
import { Frame, FrameDescription, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { Progress } from "@/components/ui/progress"
import { Skeleton } from "@/components/ui/skeleton"
import { RegionError } from "@/components/region-error"
import { monthDay, signedMoney } from "@/lib/format"
import { cn } from "@/lib/utils"

/** The hatched track and Progress indicator, the indicator green for a gain and red for a loss. */
function MiniProgress({ value, gain }: { value: number; gain: boolean }) {
  return (
    <div className="bg-muted/55 relative h-1.5 overflow-hidden rounded-full">
      <div
        className="text-muted-foreground pointer-events-none absolute inset-0 bg-[repeating-linear-gradient(-45deg,currentColor_0,currentColor_1px,transparent_0,transparent_4px)] opacity-20"
        aria-hidden="true"
      />
      <Progress
        value={value}
        className={cn(
          "absolute inset-0 gap-0",
          "**:data-[slot=progress-track]:h-full **:data-[slot=progress-track]:rounded-none **:data-[slot=progress-track]:bg-transparent",
          "**:data-[slot=progress-indicator]:rounded-none",
          gain ? "**:data-[slot=progress-indicator]:bg-success" : "**:data-[slot=progress-indicator]:bg-destructive",
        )}
      />
    </div>
  )
}

interface Row {
  name: string
  /** The ticker, in the block's mono code slot. */
  code?: string
  /** The date, in its muted slot. */
  note?: string
  title?: string
  amount: number | null
}

const tone = (n: number | null) => (n === null || n === 0 ? "text-foreground" : n > 0 ? "text-success" : "text-destructive")
const unmatchedNote = (n: number) => `${n === 1 ? "1 sale" : `${n} sales`} could not be matched to the buys it closed, so ${n === 1 ? "it is" : "they are"} left out.`

export function GuruBreakdown({ performance, error, onRetry }: { performance: GuruPerformance | null; error: string | null; onRetry: () => void }) {
  const rows: Row[] = performance
    ? [
        ...(performance.best ? [{ name: "Best call", code: performance.best.symbol, note: monthDay(`${performance.best.closed_on}T12:00:00Z`), title: performance.best.excerpt ?? undefined, amount: Number(performance.best.profit_usd) }] : []),
        ...(performance.worst ? [{ name: "Worst call", code: performance.worst.symbol, note: monthDay(`${performance.worst.closed_on}T12:00:00Z`), title: performance.worst.excerpt ?? undefined, amount: Number(performance.worst.profit_usd) }] : []),
        { name: "Unrealized P&L", amount: performance.unrealized_usd === null ? null : Number(performance.unrealized_usd) },
      ]
    : []
  const largest = Math.max(1e-9, ...rows.map((r) => Math.abs(r.amount ?? 0)))
  return (
    <Frame>
      <FrameHeader>
        <FrameTitle>Breakdown</FrameTitle>
        <FrameDescription>Best and worst call, and what is still open</FrameDescription>
      </FrameHeader>
      <FramePanel className="flex flex-col gap-5">
        {!performance && !error && <Skeleton role="status" aria-label="Loading breakdown" className="h-32 w-full" />}
        {error && <RegionError title="Performance did not load" message={error} onRetry={onRetry} />}
        {rows.map((row) => (
          <div key={row.name} className="flex flex-col gap-2">
            <div className="flex items-center justify-between gap-3">
              <span className="flex min-w-0 items-baseline gap-1.5" title={row.title}>
                <span className="text-foreground truncate text-sm font-medium">{row.name}</span>
                {row.code && <span className="text-muted-foreground shrink-0 font-mono text-[11px]">{row.code}</span>}
              </span>
              <div className="flex shrink-0 items-center gap-2.5 text-xs">
                {row.note && <span className="text-muted-foreground tabular-nums">{row.note}</span>}
                <span className={cn("min-w-14 text-right font-medium tabular-nums", tone(row.amount))}>{row.amount === null ? "—" : signedMoney(row.amount)}</span>
              </div>
            </div>
            <MiniProgress value={row.amount === null ? 0 : (Math.abs(row.amount) / largest) * 100} gain={(row.amount ?? 0) >= 0} />
          </div>
        ))}
        {performance && performance.unmatched_sells > 0 && (
          <div className="flex items-start justify-between gap-3">
            <span className="text-foreground text-sm font-medium">Unmatched sells</span>
            <span className="text-foreground text-xs font-medium tabular-nums">{performance.unmatched_sells}</span>
          </div>
        )}
        {performance && performance.unmatched_sells > 0 && <p className="text-muted-foreground -mt-3 text-xs">{unmatchedNote(performance.unmatched_sells)}</p>}
        {performance && performance.closed_trades === 0 && <p className="text-muted-foreground text-xs">No closed trades yet, so there is no best or worst call.</p>}
      </FramePanel>
    </Frame>
  )
}
