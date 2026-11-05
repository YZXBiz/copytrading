// The comparison table of the Gurus screen: the layout of a movers table (a name with a line under it, a status badge, then
// figures with an arrow and a gain or loss colour), filled with the gurus the setup copies. Changed from the block: the
// data, the columns, the rows open a guru's page, headers sort, and the figures roll. The title and search are left out:
// the page already says "Gurus", and a handful of rows needs no search.
import { ArrowDown01Icon as ArrowDownIcon } from "@/components/icons/ArrowDown01Icon"
import { TrendingDownIcon } from "@/components/icons/TrendingDownIcon"
import { TrendingUpIcon } from "@/components/icons/TrendingUpIcon"
import { useState, type ReactNode } from "react"
import type { AccountOverview, AccountOverviewPage, GuruDayStatsPage, GuruPerformance } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Frame, FramePanel } from "@/components/reui/frame"
import { RegionError } from "@/components/region-error"
import { RollingNumber } from "@/components/rolling-number"
import { Skeleton } from "@/components/ui/skeleton"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { accountCopying, badgeVariant, COPYING_TITLE } from "@/features/account/copying"
import { USD_SIGNED_OPTIONS } from "@/features/account/balance-panel/format"
import { isOpenCall } from "@/features/activity/outcome"
import { dayWindow } from "@/features/activity/time"
import { href, navigate } from "@/features/shell/route"
import { readClock } from "@/lib/clock"
import { type Loaded, useResult } from "@/lib/use-result"
import { cn } from "cn"
import { COMPARE_SORTS, type CompareSort, type Guru, guruHoldings, rankGurus, trendRows, winRate } from "./model"
import { useGuruPerformances } from "./use-gurus"

const COUNT = { maximumFractionDigits: 0 } as const
const PERCENT = { style: "percent", maximumFractionDigits: 0 } as const

/** What a figure shows until it is read, when it could not be read, and once it is. */
type Figure<T> = { status: "loading" } | { status: "error"; error: string } | { status: "ready"; value: T }

const loading = <T,>(): Figure<T> => ({ status: "loading" })
const fromLoaded = <T, U>(state: Loaded<T>, pick: (data: T) => U): Figure<U> =>
  state.status === "ready" ? { status: "ready", value: pick(state.data) } : state.status === "error" ? state : loading()

const tone = (n: number) => (n > 0 ? "text-success" : n < 0 ? "text-destructive" : "text-foreground")

/** One figure: a skeleton while it loads, "Not loaded" (the reason on hover) when it failed, otherwise what `show` makes of it. */
function Cell<T>({ figure, show }: { figure: Figure<T>; show: (value: T) => ReactNode }) {
  if (figure.status === "loading") return <Skeleton className="h-4 w-14" aria-label="Loading" />
  if (figure.status === "error") return <span title={figure.error} className="text-destructive text-xs">Not loaded</span>
  return <>{show(figure.value)}</>
}

/** A figure over the line that explains it. */
function Stacked({ value, line }: { value: ReactNode; line?: ReactNode }) {
  return (
    <div className="flex flex-col">
      <span className="text-foreground text-sm font-medium tabular-nums">{value}</span>
      <span className="text-muted-foreground text-xs tabular-nums">{line ?? " "}</span>
    </div>
  )
}

/** A gain or loss with its arrow and colour; nothing to show reads as a dash. */
function Gain({ value, line }: { value: number | null; line?: ReactNode }) {
  const Arrow = value === null || value === 0 ? null : value > 0 ? TrendingUpIcon : TrendingDownIcon
  return (
    <div className="flex flex-col">
      <span className={cn("flex items-center gap-1.5 text-sm font-medium tabular-nums", value === null ? "text-muted-foreground" : tone(value))}>
        {Arrow && <Arrow className="size-4 shrink-0" aria-hidden="true" />}
        <RollingNumber value={value} format={USD_SIGNED_OPTIONS} />
      </span>
      <span className="text-muted-foreground text-xs">{line ?? " "}</span>
    </div>
  )
}

/** The cumulative realized profit as a line, in the colour of where it ended; nothing before two points. */
function Sparkline({ series, now }: { series: GuruPerformance["series"]; now: Date }) {
  const rows = trendRows(series, null, now)
  if (rows.length < 2) return null
  const [w, h, pad] = [64, 24, 2]
  const values = rows.map((r) => r.value)
  const [low, high] = [Math.min(...values), Math.max(...values)]
  const x = (i: number) => pad + (i / (rows.length - 1)) * (w - 2 * pad)
  const y = (v: number) => h - pad - (high === low ? 0.5 : (v - low) / (high - low)) * (h - 2 * pad)
  const path = rows.map((r, i) => `${i === 0 ? "M" : "L"}${x(i).toFixed(1)} ${y(r.value).toFixed(1)}`).join(" ")
  return (
    <svg role="img" aria-label="Realized profit over time" viewBox={`0 0 ${w} ${h}`} width={w} height={h} className={cn("hidden shrink-0 @4xl:block", tone(values.at(-1)!))}>
      <path d={path} fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

function SortHead({ id, sort, onSort, children }: { id: CompareSort; sort: CompareSort; onSort: (id: CompareSort) => void; children: ReactNode }) {
  const active = sort === id
  return (
    <TableHead aria-sort={active ? "descending" : "none"} className="text-muted-foreground px-3.5 text-sm">
      <button type="button" onClick={() => onSort(id)} className={cn("hover:text-foreground inline-flex items-center gap-1 transition-colors", active && "text-foreground")}>
        {children}
        {active && <ArrowDownIcon className="size-3.5" aria-hidden="true" />}
      </button>
    </TableHead>
  )
}

interface Row {
  guru: Guru
  name: string
  today: Figure<{ posts: number; traded: number; waiting: number }>
  performance: Figure<GuruPerformance | null>
  held: Figure<ReturnType<typeof guruHoldings>>
  copying: Figure<{ title: string; variant: ReturnType<typeof badgeVariant> } | null>
  realized: number | null
  winRate: number | null
  posts: number | null
}

/** The gurus side by side: copying state, posts today, win rate, realized profit and what is still held. Opening a row opens that guru. */
export function GuruLeaderboard({ gurus, accounts, setUpAccountIds }: { gurus: Guru[]; accounts: Loaded<AccountOverviewPage>; setUpAccountIds: Set<string> }) {
  const now = readClock()
  const window_ = dayWindow(now)
  const day = useResult<GuruDayStatsPage>(() => window.copytrading.read.getGuruDayStats(window_), `day:${window_.day_start}`, 30_000)
  const status = useResult(() => window.copytrading.read.getStatus(), "status", 5000)
  const performances = useGuruPerformances(gurus)
  const [sort, setSort] = useState<CompareSort>("realized")

  const built = gurus.map((guru): Row => {
      const stats = day.status === "ready" ? day.data.gurus.find((s) => s.guru_id === guru.id) : undefined
      const today = fromLoaded(day, () => ({ posts: stats?.posts ?? 0, traded: stats?.traded ?? 0, waiting: (stats?.waiting ?? []).filter((p) => isOpenCall(p, now)).length }))
      const read = performances.status === "ready" ? performances.data[guru.id]! : null
      const performance: Figure<GuruPerformance | null> = read ? (read.ok ? { status: "ready", value: read.value } : { status: "error", error: read.error }) : performances.status === "error" ? performances : loading()
      const held = fromLoaded(accounts, (data) => guruHoldings(guru.id, data.items, setUpAccountIds))
      const copying = fromLoaded(accounts, (data) => {
        const states = guru.accounts.flatMap((a) => data.items.find((o: AccountOverview) => o.account_id === a.id) ?? []).map((o) => accountCopying(o, status.status === "ready" ? status.data : null))
        const state = states.find((s) => s.word !== "copying") ?? states[0]
        return state ? { title: COPYING_TITLE[state.word], variant: badgeVariant(state) } : null
      })
      const perf = performance.status === "ready" ? performance.value : null
      return {
        guru,
        name: guru.name,
        today,
        performance,
        held,
        copying,
        realized: perf ? Number(perf.realized_usd) : null,
        winRate: perf ? winRate(perf) : null,
        posts: today.status === "ready" ? today.value.posts : null,
      }
    })
  const rows = rankGurus(built, sort)

  const failed = day.status === "error" ? { title: "Today's posts did not load", error: day.error, retry: day.retry } : performances.status === "error" ? { title: "Profit and loss did not load", error: performances.error, retry: performances.retry } : null

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-4">
      {failed && <RegionError title={failed.title} message={failed.error} onRetry={failed.retry} />}
      <Frame stacked className="@container w-full">
        <FramePanel className="p-0!">
          <Table>
            <TableHeader className="bg-muted/50">
              <TableRow>
                <TableHead className="text-muted-foreground ps-3.5 text-sm">Guru</TableHead>
                <TableHead className="text-muted-foreground px-3.5 text-sm">Copying</TableHead>
                <SortHead id="posts" sort={sort} onSort={setSort}>Posts today</SortHead>
                <SortHead id="winRate" sort={sort} onSort={setSort}>Win rate</SortHead>
                <SortHead id="realized" sort={sort} onSort={setSort}>Realized P&amp;L</SortHead>
                <TableHead className="text-muted-foreground px-3.5 text-sm">Open P&amp;L</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((row) => {
                const perf = row.performance
                return (
                  <TableRow key={row.guru.id} className="cursor-pointer" onClick={() => navigate("gurus", row.guru.id)}>
                    <TableCell className="px-3.5 py-3">
                      <div className="flex min-w-0 items-center gap-2">
                        <span aria-hidden="true" className="bg-muted text-muted-foreground flex size-8 shrink-0 items-center justify-center rounded-full text-sm font-medium">
                          {[...row.name][0]}
                        </span>
                        <div className="min-w-0">
                          <a href={href("gurus", row.guru.id)} className="text-foreground block truncate text-sm font-medium outline-none hover:underline focus-visible:underline" onClick={(e) => e.stopPropagation()}>
                            {row.name}
                          </a>
                          <div className="text-muted-foreground truncate text-xs">{row.guru.accounts.map((a) => a.id).join(", ")}</div>
                        </div>
                      </div>
                    </TableCell>
                    <TableCell className="px-3.5 py-3">
                      <div className="flex items-center gap-1.5">
                        <Cell figure={row.copying} show={(c) => (c ? <Badge variant={c.variant} size="lg">{c.title}</Badge> : <Badge variant="outline" size="lg">Not started</Badge>)} />
                        {row.guru.accounts.some((a) => a.environment === "live") && <Badge variant="warning-light" size="lg">Live</Badge>}
                      </div>
                    </TableCell>
                    <TableCell className="px-3.5 py-3">
                      <Cell
                        figure={row.today}
                        show={(p) => <Stacked value={<RollingNumber value={p.posts} format={COUNT} />} line={`${p.traded} traded · ${p.waiting} waiting`} />}
                      />
                    </TableCell>
                    <TableCell className="px-3.5 py-3">
                      <Cell
                        figure={perf}
                        show={(p) => {
                          const rate = p ? winRate(p) : null
                          return <Stacked value={<RollingNumber value={rate} format={PERCENT} />} line={p && rate !== null ? `${p.winning_trades} of ${p.closed_trades}` : "No closed trades"} />
                        }}
                      />
                    </TableCell>
                    <TableCell className="px-3.5 py-3">
                      <Cell
                        figure={perf}
                        show={(p) => (
                          <div className="flex items-center gap-3">
                            <Gain value={p ? Number(p.realized_usd) : null} line={p && p.closed_trades === 0 ? "No sales closed" : undefined} />
                            {p && <Sparkline series={p.series} now={now} />}
                          </div>
                        )}
                      />
                    </TableCell>
                    <TableCell className="px-3.5 py-3">
                      <Cell
                        figure={row.held}
                        show={(h) => <Gain value={h ? h.gain : null} line={h ? (h.stocks === 1 ? "1 stock" : `${h.stocks} stocks`) : "Nothing held"} />}
                      />
                    </TableCell>
                  </TableRow>
                )
              })}
            </TableBody>
          </Table>
        </FramePanel>
      </Frame>
    </div>
  )
}
