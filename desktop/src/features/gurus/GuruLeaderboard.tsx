// The Gurus screen for two or more gurus: one row each with copying state, posts today, win rate, realized profit with its line,
// and what is still held. Headers sort; a guru's name opens their page.
import { useMemo, type ReactNode } from "react"
import type { AccountOverview, AccountOverviewPage, GuruDayStatsPage, GuruPerformance } from "../../../shared/contract"
import { AnimatedCounter } from "@/components/arc/animated-counter/animated-counter"
import { Badge, type BadgeTone } from "@/components/arc/badge/badge"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import Sparkline from "@/components/arc/sparkline/sparkline"
import { SortableDataTable, type DataColumn } from "@/components/arc/sortable-data-table/sortable-data-table"
import { RegionAlert } from "@/features/activity/RegionAlert"
import { accountCopying, badgeTone, COPYING_TITLE } from "@/features/account/copying"
import { isOpenCall } from "@/features/activity/outcome"
import { dayWindow } from "@/features/activity/time"
import { href } from "@/features/shell/route"
import { monthDay } from "@/lib/format"
import { readClock } from "@/lib/clock"
import { type Loaded, useResult } from "@/lib/use-result"
import { type Guru, guruHoldings, trendRows, winRate } from "./model"
import { useGuruPerformances } from "./use-gurus"
import styles from "./gurus.module.css"

/** What a figure shows until it is read, when it could not be read, and once it is. */
type Figure<T> = { status: "loading" } | { status: "error"; error: string } | { status: "ready"; value: T }

const loading = <T,>(): Figure<T> => ({ status: "loading" })
const fromLoaded = <T, U>(state: Loaded<T>, pick: (data: T) => U): Figure<U> =>
  state.status === "ready" ? { status: "ready", value: pick(state.data) } : state.status === "error" ? state : loading()

const gainTone = (n: number | null) => (n === null || n === 0 ? undefined : n > 0 ? "gain" : "loss")

/** One figure: a bar while it loads, "Not loaded" (the reason on hover) when it failed, otherwise what `show` makes of it. */
function Cell<T>({ figure, show }: { figure: Figure<T>; show: (value: T) => ReactNode }) {
  if (figure.status === "loading") return <Skeleton label="Loading" lines={1} className={styles.cellLoading} />
  if (figure.status === "error") return <span title={figure.error} className={styles.cellError}>Not loaded</span>
  return <>{show(figure.value)}</>
}

/** A figure over the line that explains it. */
function Stacked({ value, line }: { value: ReactNode; line?: ReactNode }) {
  return (
    <div className={styles.stacked}>
      <span>{value}</span>
      <small>{line}</small>
    </div>
  )
}

/** A gain or loss with its colour; nothing to show reads as "None". */
function Gain({ value, line }: { value: number | null; line?: ReactNode }) {
  return (
    <div className={styles.stacked} data-tone={gainTone(value)}>
      <span>{value === null ? "None" : <AnimatedCounter value={Math.abs(value)} prefix={`${value < 0 ? "−" : value > 0 ? "+" : ""}$`} decimals={2} />}</span>
      <small>{line}</small>
    </div>
  )
}

/** The cumulative realized profit as a line, in the colour of where it ended; nothing before two points. */
function Line({ series }: { series: GuruPerformance["series"] }) {
  const rows = trendRows(series, null, readClock())
  const key = rows.map((r) => r.value).join(",")
  // The same array while the figures are the same, so a re-read of unchanged figures does not redraw the line.
  const values = useMemo(() => rows.map((r) => r.value), [key]) // eslint-disable-line react-hooks/exhaustive-deps
  if (rows.length < 2) return null
  return (
    <span className={styles.spark}>
      <Sparkline data={values} label="Realized profit over time" tone={values.at(-1)! >= 0 ? "success" : "danger"} width={72} height={28} />
    </span>
  )
}

interface Row extends Record<string, unknown> {
  id: string
  guru: Guru
  name: string
  today: Figure<{ posts: number; traded: number; waiting: number }>
  performance: Figure<GuruPerformance | null>
  held: Figure<ReturnType<typeof guruHoldings>>
  copying: Figure<{ title: string; tone: BadgeTone } | null>
  /** The values the headers sort by: null until read. */
  posts: number | null
  winRate: number | null
  realized: number | null
  open: number | null
}

/** The gurus side by side: copying state, posts today, win rate, realized profit and what is still held. */
export function GuruLeaderboard({ gurus, accounts, setUpAccountIds }: { gurus: Guru[]; accounts: Loaded<AccountOverviewPage>; setUpAccountIds: Set<string> }) {
  const now = readClock()
  const window_ = dayWindow(now)
  const day = useResult<GuruDayStatsPage>(() => window.copytrading.read.getGuruDayStats(window_), `day:${window_.day_start}`, 30_000)
  const status = useResult(() => window.copytrading.read.getStatus(), "status", 5000)
  const performances = useGuruPerformances(gurus)

  const rows = gurus.map((guru): Row => {
    const stats = day.status === "ready" ? day.data.gurus.find((s) => s.guru_id === guru.id) : undefined
    const today = fromLoaded(day, () => ({ posts: stats?.posts ?? 0, traded: stats?.traded ?? 0, waiting: (stats?.waiting ?? []).filter((p) => isOpenCall(p, now)).length }))
    const read = performances.status === "ready" ? performances.data[guru.id]! : null
    const performance: Figure<GuruPerformance | null> = read ? (read.ok ? { status: "ready", value: read.value } : { status: "error", error: read.error }) : performances.status === "error" ? performances : loading()
    const held = fromLoaded(accounts, (data) => guruHoldings(guru.id, data.items, setUpAccountIds))
    const copying = fromLoaded(accounts, (data) => {
      const states = guru.accounts.flatMap((a) => data.items.find((o: AccountOverview) => o.account_id === a.id) ?? []).map((o) => accountCopying(o, status.status === "ready" ? status.data : null))
      const state = states.find((s) => s.word !== "copying") ?? states[0]
      return state ? { title: COPYING_TITLE[state.word], tone: badgeTone(state) } : null
    })
    const perf = performance.status === "ready" ? performance.value : null
    return {
      id: guru.id,
      guru,
      name: guru.name,
      today,
      performance,
      held,
      copying,
      posts: today.status === "ready" ? today.value.posts : null,
      winRate: perf ? winRate(perf) : null,
      realized: perf ? Number(perf.realized_usd) : null,
      open: held.status === "ready" && held.value ? held.value.gain : null,
    }
  })

  const columns = useMemo<DataColumn<Row>[]>(
    () => [
      {
        key: "name",
        label: "Guru",
        sortable: true,
        width: 190,
        render: (_, row) => (
          <div className={styles.who}>
            <span aria-hidden="true">{[...row.name][0]}</span>
            <div>
              <a href={href("gurus", row.guru.id)}>{row.name}</a>
              <small>{row.guru.accounts.map((a) => a.id).join(", ")}</small>
            </div>
          </div>
        ),
      },
      {
        key: "copying",
        label: "Copying",
        width: 120,
        render: (_, row) => (
          <div className={styles.badges}>
            <Cell figure={row.copying} show={(c) => (c ? <Badge tone={c.tone}>{c.title}</Badge> : <Badge tone="neutral" outline>Not started</Badge>)} />
            {row.guru.accounts.some((a) => a.environment === "live") && <Badge tone="warning">Live</Badge>}
          </div>
        ),
      },
      {
        key: "posts",
        label: "Posts today",
        sortable: true,
        width: 130,
        render: (_, row) => <Cell figure={row.today} show={(p) => <Stacked value={<AnimatedCounter value={p.posts} />} line={`${p.traded} traded, ${p.waiting} waiting`} />} />,
      },
      {
        key: "winRate",
        label: "Win rate",
        sortable: true,
        width: 110,
        render: (_, row) => (
          <Cell
            figure={row.performance}
            show={(p) => {
              const rate = p ? winRate(p) : null
              return <Stacked value={rate === null ? "None" : <AnimatedCounter value={Math.round(rate * 100)} suffix="%" />} line={p && rate !== null ? `${p.winning_trades} of ${p.closed_trades}` : "No closed trades"} />
            }}
          />
        ),
      },
      {
        key: "realized",
        label: "Realized P&L",
        sortable: true,
        width: 200,
        render: (_, row) => (
          <Cell
            figure={row.performance}
            show={(p) => (
              <div className={styles.withLine}>
                <Gain value={p ? Number(p.realized_usd) : null} line={p && p.closed_trades === 0 ? "No sales closed" : p?.series[0] ? `Since ${monthDay(`${p.series[0].day}T12:00:00Z`)}` : undefined} />
                {p && <Line series={p.series} />}
              </div>
            )}
          />
        ),
      },
      {
        key: "open",
        label: "Open P&L",
        sortable: true,
        width: 130,
        render: (_, row) => <Cell figure={row.held} show={(h) => <Gain value={h ? h.gain : null} line={h ? (h.stocks === 1 ? "1 stock" : `${h.stocks} stocks`) : "Nothing held"} />} />,
      },
    ],
    [],
  )

  const failed = day.status === "error" ? { title: "Today's posts did not load", error: day.error, retry: day.retry } : performances.status === "error" ? { title: "Profit and loss did not load", error: performances.error, retry: performances.retry } : null

  return (
    <div className={styles.page}>
      {failed && <RegionAlert title={failed.title} message={failed.error} onRetry={failed.retry} />}
      <div className={styles.tablePanel}>
        <div className={styles.tableScroll}>
          <SortableDataTable rows={rows} columns={columns} rowKey="id" caption="Gurus" emptyMessage="No gurus yet" defaultSort={{ key: "realized", direction: "desc" }} />
        </div>
      </div>
    </div>
  )
}
