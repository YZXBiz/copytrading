import { useMemo, useRef, useState } from "react"
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
import { balanceRows } from "./balance-rows"
import { dayChange } from "./model"

const RANGES: { value: HistoryRange; label: string }[] = [
  { value: "day", label: "1D" },
  { value: "week", label: "1W" },
  { value: "month", label: "1M" },
  { value: "three_months", label: "3M" },
  { value: "year", label: "1Y" },
]

/** What the account can spend and what CopyTrading has put to work: a label, then its figure. */
function Figure({ label, value, note }: { label: string; value: string; note?: string }) {
  return (
    <div className="flex items-baseline gap-1.5 text-sm">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="tabular-nums">
        {value}
        {note && <span className="text-muted-foreground ms-1.5 text-xs">{note}</span>}
      </dd>
    </div>
  )
}

/**
 * The page's focal point, as in Origin, Gemini and Copilot Money: the balance as one large figure with today's change
 * beside it, what the account can spend in a quiet row under it, the line (ReUI Balance Tracker) under that, the range
 * beside the figure. The change is today's against yesterday's close; the line's own change over a range is in its readout.
 */
export function BalanceChart({ account }: { account: AccountOverview }) {
  const accountId = account.account_id
  const [range, setRange] = useState<HistoryRange>("month")
  // The reply carries its own range: a change of range renders once with the old reply still in hand.
  const history = useResult(
    async () => {
      const result = await window.copytrading.read.getEquityHistory({ account_id: accountId, range })
      return result.ok ? { ok: true as const, value: { range, history: result.value } } : result
    },
    `${accountId}:${range}`,
    60_000,
  )
  const balance = account.balance
  const today = dayChange(account)

  const data = history.status === "ready" ? history.data : null
  // Stable between the page's own re-renders: new rows would redraw the line.
  const read = useMemo(() => (data?.history ? { range: data.range, rows: balanceRows(data.history.points.map((p) => ({ at: p.at, equity: Number(p.equity) }))) } : null), [data])
  // A new range keeps drawing the last one until its points land, so the line morphs instead of being redrawn.
  const last = useRef(read)
  if (read) last.current = read
  const pending = history.status === "loading" || (data !== null && data.range !== range)
  const shown = pending ? last.current : read
  const rows = shown?.rows ?? []
  const switching = pending && shown !== null
  const up = (rows.at(-1)?.balance ?? 0) >= (rows[0]?.balance ?? 0)
  const tick = (key: string) => (shown?.range === "day" ? timeOfDay(key) : monthDay(key))

  return (
    <Frame spacing="default">
      <FramePanel className="flex flex-col gap-5">
        <div className="flex flex-wrap items-start justify-between gap-x-6 gap-y-3">
          <div className="flex flex-col gap-3">
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
            <dl className="flex flex-wrap gap-x-6 gap-y-1">
              <Figure label="Cash" value={money(balance?.cash)} />
              <Figure label="Buying power" value={money(balance?.buying_power)} />
              <Figure
                label="Invested by CopyTrading"
                value={money(account.total_exposure_usd ?? "0")}
                note={account.pending_orders ? `${account.pending_orders} orders waiting` : undefined}
              />
            </dl>
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
        {pending && !switching && <Skeleton className="h-72 w-full" role="status" aria-label="Loading balance history" />}
        {history.status === "error" && <RegionError title="Balance history did not load" message={history.error} onRetry={history.retry} />}
        {!pending && history.status === "ready" && rows.length < 2 && (
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
        {rows.length >= 2 && (!pending || switching) && history.status !== "error" && <BalancePlot rows={rows} tick={tick} up={up} />}
      </FramePanel>
    </Frame>
  )
}
