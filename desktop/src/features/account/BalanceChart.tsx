import { useMemo, useState } from "react"
import { ArrowDownIcon, ArrowUpIcon, ChartLineIcon } from "lucide-react"
import type { AccountOverview, HistoryRange } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Frame, FramePanel } from "@/components/reui/frame"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Empty, EmptyContent, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { Skeleton } from "@/components/ui/skeleton"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { money, monthDay, signedMoney, signedPercent, timeOfDay } from "@/lib/format"
import { useResult } from "@/lib/use-result"
import { BalancePlot } from "./BalancePlot"
import { dayChange } from "./model"

const RANGES: { value: HistoryRange; label: string }[] = [
  { value: "day", label: "1D" },
  { value: "week", label: "1W" },
  { value: "month", label: "1M" },
  { value: "three_months", label: "3M" },
  { value: "year", label: "1Y" },
]

/** One figure of the strip under the chart: its label, then the number. `note` is only for a fact that changes what the owner does. */
function Fact({ label, value, note }: { label: string; value: string; note?: string }) {
  return (
    <div className="flex min-w-0 flex-col gap-1 sm:not-first:border-s sm:not-first:ps-(--frame-panel-px)">
      <dt className="text-muted-foreground text-sm">{label}</dt>
      <dd className="flex flex-col gap-0.5">
        <span className="text-xl font-semibold tracking-tight tabular-nums">{value}</span>
        {note && <span className="text-muted-foreground text-xs tabular-nums">{note}</span>}
      </dd>
    </div>
  )
}

/**
 * The page's focal point, as in Origin, Gemini and Copilot Money: the balance as one large figure with today's change
 * beside it, the line (ReUI Balance Tracker) directly under it, the range beside the figure, then what the account can
 * spend. The change is today's against yesterday's close; the line's own change over a range is in its readout.
 */
export function BalanceChart({ account }: { account: AccountOverview }) {
  const accountId = account.account_id
  const [range, setRange] = useState<HistoryRange>("month")
  const history = useResult(() => window.copytrading.read.getEquityHistory({ account_id: accountId, range }), `${accountId}:${range}`, 60_000)
  const balance = account.balance
  const today = dayChange(account)

  const data = history.status === "ready" ? history.data : null
  // Stable between the page's own re-renders: a new array would redraw the line.
  const points = useMemo(() => data?.points.map((p) => ({ at: p.at, equity: Number(p.equity) })) ?? [], [data])
  const up = (points.at(-1)?.equity ?? 0) >= (points[0]?.equity ?? 0)
  const tick = (at: string) => (range === "day" ? timeOfDay(at) : monthDay(at))

  return (
    <Frame spacing="default">
      <FramePanel className="flex flex-col gap-5">
        <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-3">
          <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
            <span className="text-4xl leading-none font-semibold tracking-tight tabular-nums">{balance ? money(balance.equity) : "—"}</span>
            {balance && today ? (
              <div className="flex items-center gap-2">
                <Badge variant={today.amount >= 0 ? "success-light" : "destructive-light"}>
                  {today.amount >= 0 ? <ArrowUpIcon aria-hidden="true" /> : <ArrowDownIcon aria-hidden="true" />}
                  {signedPercent(today.fraction, 2)}
                </Badge>
                <span className="text-muted-foreground text-sm tabular-nums">{signedMoney(today.amount)} today</span>
              </div>
            ) : (
              !balance && <span className="text-muted-foreground text-sm">Not read from the broker yet</span>
            )}
          </div>
          <ToggleGroup
            value={[range]}
            onValueChange={(next) => next[0] && setRange(next[0] as HistoryRange)}
            variant="outline"
            size="sm"
            spacing={0}
            aria-label="Balance range"
          >
            {RANGES.map((r) => (
              <ToggleGroupItem key={r.value} value={r.value} className="text-muted-foreground data-pressed:bg-card data-pressed:text-foreground dark:data-pressed:bg-muted">
                {r.label}
              </ToggleGroupItem>
            ))}
          </ToggleGroup>
        </div>
        {history.status === "loading" && <Skeleton className="h-72 w-full" role="status" aria-label="Loading balance history" />}
        {history.status === "error" && <RegionError title="Balance history did not load" message={history.error} onRetry={history.retry} />}
        {history.status === "ready" && points.length < 2 && (
          <Empty className="h-72">
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
        {history.status === "ready" && points.length >= 2 && <BalancePlot points={points} tick={tick} up={up} />}
      </FramePanel>
      <FramePanel>
        <dl className="grid grid-cols-1 gap-4 sm:grid-cols-3 sm:gap-0">
          <Fact label="Cash" value={money(balance?.cash)} />
          <Fact label="Buying power" value={money(balance?.buying_power)} />
          <Fact
            label="Invested by CopyTrading"
            value={money(account.total_exposure_usd ?? "0")}
            note={account.pending_orders ? `${account.pending_orders} orders waiting` : undefined}
          />
        </dl>
      </FramePanel>
    </Frame>
  )
}
