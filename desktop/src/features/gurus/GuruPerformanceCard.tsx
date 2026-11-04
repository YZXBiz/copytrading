// ReUI's Wallet Balances (chart-3), installed as shipped: a Frame of balance cards, each with its icon tile, label, figure and
// change, and the first with its line over a dotted bed. The line is the guru's cumulative realized profit by day; the
// other cards carry the same structure without a line. Changed from the block: the data, and the y-axis fits the series.
import { type ReactNode, useId, useState } from "react"
import { ArrowDownRightIcon, ArrowUpRightIcon, CircleDollarSignIcon, HourglassIcon, TargetIcon, TrendingUpIcon } from "lucide-react"
import { Line, LineChart, XAxis, YAxis } from "recharts"
import type { ClosedTrade, GuruPerformance } from "../../../shared/contract"
import { RegionError } from "@/components/region-error"
import { Frame, FramePanel } from "@/components/reui/frame"
import { type ChartConfig, ChartContainer } from "@/components/ui/chart"
import { Empty, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { Skeleton } from "@/components/ui/skeleton"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { parseDec } from "@/features/account/decimal"
import { monthDay, percent, signedMoney } from "@/lib/format"
import { useResult } from "@/lib/use-result"
import { cn } from "@/lib/utils"
import type { Guru } from "./model"

const num = (text: string | null | undefined) => (parseDec(text) === null ? null : Number(text))
const tone = (n: number | null) => (n === null || n === 0 ? undefined : n > 0 ? "text-success" : "text-destructive")

function DottedChartBackground() {
  const id = useId().replace(/:/g, "")
  const patternId = `${id}-dots`
  const maskId = `${id}-fade`

  return (
    <svg
      aria-hidden="true"
      className="text-foreground/20 pointer-events-none absolute inset-x-0 bottom-0 h-24 w-full"
      fill="none"
      preserveAspectRatio="none"
      viewBox="0 0 320 96"
      xmlns="http://www.w3.org/2000/svg"
    >
      <defs>
        <pattern id={patternId} height="1" patternTransform="matrix(4.5 0 0 4.5 0 0)" patternUnits="userSpaceOnUse" preserveAspectRatio="none" viewBox="0 0 9 9" width="1">
          <g>
            <rect fill="currentColor" height="2" rx="1" width="2" x="2" y="2" />
          </g>
        </pattern>
        <linearGradient id={maskId} x1="0" x2="0" y1="0" y2="1">
          <stop offset="0" stopColor="white" stopOpacity="0" />
          <stop offset="0.28" stopColor="white" stopOpacity="0.45" />
          <stop offset="1" stopColor="white" />
        </linearGradient>
        <mask id={`${maskId}-mask`}>
          <rect fill={`url(#${maskId})`} height="96" width="320" />
        </mask>
      </defs>
      <rect fill={`url(#${patternId})`} height="96" mask={`url(#${maskId}-mask)`} width="320" />
    </svg>
  )
}

function IconTile({ iconBg, children }: { iconBg: string; children: ReactNode }) {
  return (
    <div
      className={cn(
        "relative isolate flex size-10 shrink-0 items-center justify-center overflow-hidden rounded-md shadow-[0_1px_3px_0_rgba(0,0,0,0.14)] dark:shadow-[0_1px_3px_0_rgba(0,0,0,0.35)] [&_svg]:size-5 [&_svg]:text-white",
        "border-background dark:border-border border-2",
        iconBg,
      )}
    >
      <span
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 z-[1] [background-image:radial-gradient(48.05%_48.05%_at_50%_5.95%,rgba(255,255,255,0.4)_0%,rgba(255,255,255,0)_100%)]"
      />
      <span className="relative z-10">{children}</span>
    </div>
  )
}

/** The cumulative line, from nothing before the first sale. */
function PerformanceLine({ series, up }: { series: GuruPerformance["series"]; up: boolean }) {
  const chartConfig = { value: { label: "Realized", color: up ? "var(--success)" : "var(--destructive)" } } satisfies ChartConfig
  const data = [{ date: "start", value: 0 }, ...series.map((point) => ({ date: point.day, value: Number(point.cumulative_usd) }))]
  return (
    <ChartContainer config={chartConfig} className="absolute inset-x-0 bottom-0 aspect-auto h-24 w-full" initialDimension={{ width: 320, height: 96 }}>
      <LineChart accessibilityLayer data={data} margin={{ top: 10, right: 0, bottom: 12, left: 0 }}>
        <XAxis dataKey="date" hide />
        <YAxis hide domain={["dataMin", "dataMax"]} />
        <Line type="linear" dataKey="value" dot={false} isAnimationActive={false} stroke="var(--color-value)" strokeWidth={2} />
      </LineChart>
    </ChartContainer>
  )
}

interface CardProps {
  label: string
  value: string
  valueTone?: string
  detail?: ReactNode
  icon: ReactNode
  iconBg: string
  line?: ReactNode
  className?: string
}

function PerformanceCardItem({ label, value, valueTone, detail, icon, iconBg, line, className }: CardProps) {
  return (
    <FramePanel className={cn("p-0!", line ? "min-h-[178px]" : "min-h-0", className)}>
      <div className={cn("relative isolate h-full overflow-hidden", line && "min-h-[178px]")}>
        {line ? <DottedChartBackground /> : null}
        <div className="relative z-10 flex items-start gap-2.5 p-5">
          <IconTile iconBg={iconBg}>{icon}</IconTile>
          <div className="min-w-0">
            <h3 className="text-muted-foreground truncate text-sm leading-none">{label}</h3>
            <div className="mt-1 flex flex-wrap items-baseline gap-x-1.5 gap-y-1">
              <span className={cn("text-base font-medium tabular-nums", valueTone)}>{value}</span>
              {detail}
            </div>
          </div>
        </div>
        {line}
      </div>
    </FramePanel>
  )
}

const callDetail = (trade: ClosedTrade) => (
  <span className="text-muted-foreground truncate text-sm" title={trade.excerpt ?? undefined}>
    {trade.symbol}, {monthDay(`${trade.closed_on}T12:00:00Z`)}
  </span>
)

function Cards({ performance }: { performance: GuruPerformance }) {
  const realized = num(performance.realized_usd) ?? 0
  const unrealized = num(performance.unrealized_usd)
  const winRate = performance.closed_trades > 0 ? performance.winning_trades / performance.closed_trades : null
  const { best, worst } = performance
  return (
    <>
      <PerformanceCardItem
        label="Realized"
        value={signedMoney(realized)}
        valueTone={tone(realized)}
        detail={<span className="text-muted-foreground text-sm">{performance.closed_trades === 1 ? "1 closed trade" : `${performance.closed_trades} closed trades`}</span>}
        icon={<TrendingUpIcon aria-hidden="true" />}
        iconBg="bg-primary"
        line={<PerformanceLine series={performance.series} up={realized >= 0} />}
        className="@2xl:col-span-4"
      />
      <PerformanceCardItem label="Unrealized" value={unrealized === null ? "—" : signedMoney(unrealized)} valueTone={tone(unrealized)} icon={<HourglassIcon aria-hidden="true" />} iconBg="bg-primary" />
      <PerformanceCardItem
        label="Win rate"
        value={winRate === null ? "—" : percent(winRate, 0)}
        detail={<span className="text-muted-foreground text-sm">{`${performance.winning_trades} of ${performance.closed_trades}`}</span>}
        icon={<TargetIcon aria-hidden="true" />}
        iconBg="bg-primary"
      />
      <PerformanceCardItem
        label="Best call"
        value={best ? signedMoney(best.profit_usd) : "—"}
        valueTone={tone(best ? num(best.profit_usd) : null)}
        detail={best ? callDetail(best) : undefined}
        icon={<ArrowUpRightIcon aria-hidden="true" />}
        iconBg="bg-success"
      />
      <PerformanceCardItem
        label="Worst call"
        value={worst ? signedMoney(worst.profit_usd) : "—"}
        valueTone={tone(worst ? num(worst.profit_usd) : null)}
        detail={worst ? callDetail(worst) : undefined}
        icon={<ArrowDownRightIcon aria-hidden="true" />}
        iconBg="bg-destructive"
      />
    </>
  )
}

/** What one guru's copied sales made in one account: the figures and the line, or "No closed trades yet". */
export function GuruPerformanceCard({ guru }: { guru: Guru }) {
  const [chosen, setChosen] = useState(guru.accounts[0]?.id ?? "")
  const accountId = guru.accounts.some((a) => a.id === chosen) ? chosen : (guru.accounts[0]?.id ?? "")
  const result = useResult(
    () => window.copytrading.read.getGuruPerformance({ account_id: accountId, guru_id: guru.id }),
    `performance:${guru.id}:${accountId}`,
    60_000,
  )
  if (!accountId) return null
  const performance = result.status === "ready" ? result.data : null
  return (
    <section aria-label="Performance" className="flex flex-col gap-3">
      {guru.accounts.length > 1 && (
        <Tabs value={accountId} onValueChange={(next) => next && setChosen(String(next))}>
          <TabsList aria-label="Account">
            {guru.accounts.map((account) => (
              <TabsTrigger key={account.id} value={account.id}>
                {account.id}
              </TabsTrigger>
            ))}
          </TabsList>
        </Tabs>
      )}
      {result.status === "error" && <RegionError title="Performance did not load" message={result.error} onRetry={result.retry} />}
      {result.status === "loading" && <Skeleton role="status" aria-label="Loading performance" className="h-[178px] w-full" />}
      {performance && performance.closed_trades === 0 && (
        <Frame>
          <FramePanel>
            <Empty className="border-0 py-6">
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <CircleDollarSignIcon aria-hidden="true" />
                </EmptyMedia>
                <EmptyTitle>No closed trades yet</EmptyTitle>
                <EmptyDescription>{performance.unmatched_sells > 0 ? unmatchedNote(performance.unmatched_sells) : "What this guru's sales make shows up here."}</EmptyDescription>
              </EmptyHeader>
            </Empty>
          </FramePanel>
        </Frame>
      )}
      {performance && performance.closed_trades > 0 && (
        <div className="@container w-full">
          <Frame className="w-full" spacing="xs">
            <div className="grid gap-1 @2xl:grid-cols-4">
              <Cards performance={performance} />
            </div>
          </Frame>
          {performance.unmatched_sells > 0 && <p className="text-muted-foreground mt-2 text-sm">{unmatchedNote(performance.unmatched_sells)}</p>}
        </div>
      )}
    </section>
  )
}

const unmatchedNote = (n: number) => `${n === 1 ? "1 sale" : `${n} sales`} could not be matched to the buys it closed, so ${n === 1 ? "it is" : "they are"} left out.`
