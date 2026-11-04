// ReUI's Balance Tracker (chart-4), installed as shipped and wired to the account: the header tile, title and
// subtitle, the range toolbar, the figure and its change, the line, the stat strip and the footer meta line.
// Left out because the account has nothing behind them: Compare (no benchmark), the colour picker (one accent),
// and the CSV and copy exports (they need the block's toasts).
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react"
import { ChartLineIcon } from "lucide-react"
import type { AccountOverview, HistoryRange } from "../../../../shared/contract"
import {
  Frame,
  FrameDescription,
  FrameFooter,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame"
import { IconTile } from "@/components/reui/icon-tile"
import { RollingNumber } from "@/components/rolling-number"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Empty, EmptyContent, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { Skeleton } from "@/components/ui/skeleton"
import { ago, monthDay, percent, timeOfDay } from "@/lib/format"
import { useResult } from "@/lib/use-result"
import { cn } from "@/lib/utils"
import { dayChange } from "../model"
import { BalancePlot } from "./balance-plot"
import { ChartToolbar, type ChartActions } from "./chart-toolbar"
import {
  CHART_CONFIG,
  DEFAULT_VIEW,
  RANGES,
  type RangeKey,
  type ViewState,
} from "./data"
import {
  USD_OPTIONS,
  USD_SIGNED_OPTIONS,
  formatFullDay,
  formatSignedPercent,
  formatSignedUsd,
  formatUsd,
} from "./format"
import { UI_ICONS } from "./icons"
import { balanceRows, rangeStats, type BalanceRow } from "./range-view"
import {
  ACCENT_SCOPE,
  AverageKey,
  CAP_BOX,
  ChangeBadge,
  DotSeparator,
  Fact,
  SeriesKeyMark,
} from "./value-faces"

const sameView = (a: ViewState, b: ViewState) =>
  a.range === b.range && a.markers === b.markers && a.average === b.average

function Stat({
  label,
  value,
  meta,
}: {
  label: string
  value: ReactNode
  meta?: string
}) {
  return (
    <div className="flex min-w-0 flex-col gap-2 @2xl:px-(--frame-panel-px) @2xl:py-(--frame-panel-py) @2xl:not-first:border-s">
      <dt className="text-muted-foreground text-sm">{label}</dt>
      <dd className="flex min-w-0 flex-col gap-1.5">
        <span className="text-xl leading-none font-semibold tracking-tight tabular-nums">
          {value}
        </span>
        {meta ? (
          <Fact className="text-muted-foreground text-xs tabular-nums">
            {meta}
          </Fact>
        ) : null}
      </dd>
    </div>
  )
}

function LegendItem({
  glyph,
  children,
}: {
  glyph: ReactNode
  children: string
}) {
  return (
    <li className="text-muted-foreground flex h-4 items-center gap-1.5">
      {glyph}
      <span className={CAP_BOX}>{children}</span>
    </li>
  )
}

/** The window's clock for "Synced 2 min ago": it moves on every half minute. */
function useNow() {
  const [now, setNow] = useState(() => new Date())
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 30_000)
    return () => clearInterval(timer)
  }, [])
  return now
}

export function BalancePanel({
  account,
  onRefresh,
}: {
  account: AccountOverview
  /** The account, its posts, limits and state are read again. */
  onRefresh: () => void
}) {
  const accountId = account.account_id
  const [view, setView] = useState<ViewState>(DEFAULT_VIEW)
  const now = useNow()

  // The reply carries its own range: a change of range renders once with the old reply still in hand.
  const history = useResult(
    async () => {
      const result = await window.copytrading.read.getEquityHistory({ account_id: accountId, range: view.range })
      return result.ok ? { ok: true as const, value: { range: view.range, history: result.value, readAt: new Date().toISOString() } } : result
    },
    `${accountId}:${view.range}`,
    60_000,
  )
  const data = history.status === "ready" ? history.data : null
  // Stable between the page's own re-renders: new rows would redraw the line.
  const read = useMemo(
    () => (data?.history ? { range: data.range, readAt: data.readAt, rows: balanceRows(data.history.points.map((p) => ({ at: p.at, equity: Number(p.equity) }))) } : null),
    [data],
  )
  // A new range keeps drawing the last one, with its own axis labels, until its points land, so the line morphs instead of being redrawn.
  const last = useRef(read)
  if (read) last.current = read
  const pending = history.status === "loading" || (data !== null && data.range !== view.range)
  const shown = pending ? last.current : read
  const rows: BalanceRow[] = shown?.rows ?? []
  const switching = pending && shown !== null
  const refreshing = pending && shown !== null
  const stats = rows.length >= 2 ? rangeStats(rows) : null
  const range = RANGES.find((r) => r.value === (shown?.range ?? view.range))!
  const tick = (key: string) => (shown?.range === "day" ? timeOfDay(key) : monthDay(key))

  const patchView = (patch: Partial<ViewState>) =>
    setView((current) => ({ ...current, ...patch }))
  const changeRange = (next: RangeKey) => patchView({ range: next as HistoryRange })

  const actions: ChartActions = {
    refresh: () => {
      history.retry()
      onRefresh()
    },
    resetView: () => setView(DEFAULT_VIEW),
  }

  const balance = account.balance
  const today = dayChange(account)
  const equity = Number(balance?.equity)
  const share = (part: string | null | undefined) =>
    equity > 0 && part != null ? `${percent(Number(part) / equity, 0)} of the balance` : undefined
  const keyed = view.average
  const chartLabel = stats
    ? `Balance ${range.name}, from ${formatUsd(stats.open)} to ${formatUsd(stats.close)}. Arrow keys move between points.`
    : "Balance"

  return (
    <Frame spacing="default" className={cn("w-full min-w-0", ACCENT_SCOPE)}>
      <FrameHeader className="flex-row flex-wrap items-center justify-between gap-x-3 gap-y-2">
        {/* The basis wraps the toolbar below the title before the subtitle
            would truncate. */}
        <div className="flex min-w-0 flex-1 basis-56 items-center gap-3">
          <IconTile variant="frame" size="sm" aria-hidden="true">
            {UI_ICONS.wallet}
          </IconTile>
          <div className="flex min-w-0 flex-col gap-px">
            <FrameTitle role="heading" aria-level={3} className="truncate">
              {accountId}
            </FrameTitle>
            <FrameDescription className="truncate">
              {`Alpaca ${account.environment} account`}
            </FrameDescription>
          </div>
        </div>
        <ChartToolbar
          view={view}
          onRangeChange={changeRange}
          onViewChange={patchView}
          refreshing={refreshing}
          canReset={!sameView(view, DEFAULT_VIEW)}
          actions={actions}
        />
      </FrameHeader>

      <FramePanel className="flex flex-col gap-5">
        <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-4">
          <div className="flex min-w-0 flex-col gap-2.5">
            <span className="text-muted-foreground text-sm">Balance</span>
            <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
              <RollingNumber
                value={balance ? equity : null}
                format={USD_OPTIONS}
                className="text-3xl leading-none font-semibold tracking-tight tabular-nums"
              />
              {stats ? (
                <div className="flex items-center gap-2">
                  <ChangeBadge ratio={stats.changeRatio} />
                  <Fact className="text-muted-foreground text-xs tabular-nums">
                    {`${formatSignedUsd(stats.change)} ${range.name}`}
                  </Fact>
                </div>
              ) : null}
            </div>
          </div>
          {/* Keyed only once a second line joins the balance; from sm up
              the slot stays, so a layer toggle never moves the plot. */}
          <ul
            aria-label="Legend"
            aria-hidden={!keyed}
            className={cn(
              "flex flex-wrap items-center gap-x-4 gap-y-2 text-xs",
              !keyed && "invisible max-sm:hidden"
            )}
          >
            <LegendItem glyph={<SeriesKeyMark series="balance" />}>
              {CHART_CONFIG.balance.label}
            </LegendItem>
            {view.average ? (
              <LegendItem glyph={<AverageKey />}>Average</LegendItem>
            ) : null}
          </ul>
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
              <Button type="button" size="sm" variant="outline" onClick={() => (view.range === DEFAULT_VIEW.range ? history.retry() : changeRange(DEFAULT_VIEW.range))}>
                {view.range === DEFAULT_VIEW.range ? "Retry" : "Show 1 month"}
              </Button>
            </EmptyContent>
          </Empty>
        )}
        {stats && (!pending || switching) && history.status !== "error" && (
          <BalancePlot
            rows={rows}
            tick={tick}
            markers={view.markers}
            average={view.average}
            label={chartLabel}
          />
        )}
      </FramePanel>

      <FramePanel className="@container">
        <dl className="grid grid-cols-2 gap-5 @2xl:-mx-(--frame-panel-px) @2xl:-my-(--frame-panel-py) @2xl:grid-cols-4 @2xl:gap-0">
          <Stat label="Cash" value={<RollingNumber value={Number(balance?.cash)} format={USD_OPTIONS} />} meta={share(balance?.cash)} />
          <Stat label="Buying power" value={<RollingNumber value={Number(balance?.buying_power)} format={USD_OPTIONS} />} />
          <Stat
            label="Invested by CopyTrading"
            value={<RollingNumber value={Number(account.total_exposure_usd ?? 0)} format={USD_OPTIONS} />}
            meta={account.pending_orders ? `${account.pending_orders} orders waiting` : share(account.total_exposure_usd)}
          />
          <Stat
            label="Today"
            value={<RollingNumber value={today?.amount} format={USD_SIGNED_OPTIONS} />}
            meta={today ? `${formatSignedPercent(today.fraction)} from yesterday's close` : undefined}
          />
        </dl>
      </FramePanel>

      <FrameFooter className="text-muted-foreground flex-row flex-wrap items-center justify-between gap-x-4 gap-y-1 text-xs">
        <span className="flex min-w-0 items-center gap-1.5">
          <Fact>Account equity</Fact>
          <DotSeparator />
          <Fact>USD</Fact>
        </span>
        {shown ? (
          <span className="flex min-w-0 items-center gap-1.5">
            <Fact className="tabular-nums">{`As of ${formatFullDay(rows.at(-1)?.time ?? now.getTime())}`}</Fact>
            <DotSeparator />
            <Fact>{refreshing ? "Syncing" : `Synced ${ago(shown.readAt, now)}`}</Fact>
          </span>
        ) : null}
      </FrameFooter>
    </Frame>
  )
}
