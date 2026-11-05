import { useMemo, useState } from "react"
import type { AccountOverviewPage } from "../../../shared/contract"
import { RegionAlert } from "@/features/activity/RegionAlert"
import { accountCopying, badgeTone, COPYING_TITLE } from "@/features/account/copying"
import { usePosts } from "@/features/activity/use-posts"
import { dayWindow } from "@/features/activity/time"
import { readClock } from "@/lib/clock"
import { type Loaded, useResult } from "@/lib/use-result"
import { GuruActivity } from "./GuruActivity"
import { GuruBreakdown } from "./GuruBreakdown"
import { GuruHeader } from "./GuruHeader"
import { GuruKpis } from "./GuruKpis"
import { GuruPostSheet } from "./GuruPostSheet"
import { GuruTrendChart } from "./GuruTrendChart"
import { type Guru, type PostFilter, TREND_RANGES, type TrendRange, buildFeed, guruHoldings, guruStats, trendRows } from "./model"
import styles from "./gurus.module.css"

/**
 * One guru's page: header, four figures, the profit line against break-even, the breakdown beside the posts.
 * A chosen post opens in a drawer.
 */
export function GuruPage({ guru, accounts, setUpAccountIds }: { guru: Guru; accounts: Loaded<AccountOverviewPage>; setUpAccountIds: Set<string> }) {
  const now = readClock()
  const window_ = dayWindow(now)
  const day = useResult(() => window.copytrading.read.getGuruDayStats(window_), `day:${guru.id}:${window_.day_start}`, 30_000)
  const posts = usePosts((before_seq, limit) => window.copytrading.read.getGuruActivity({ guru_id: guru.id, before_seq, limit }), `guru:${guru.id}`)
  const status = useResult(() => window.copytrading.read.getStatus(), "status", 5000)
  const [filter, setFilter] = useState<PostFilter>("all")
  const [open, setOpen] = useState<number | null>(null)
  const [range, setRange] = useState<TrendRange>("all")
  const [chosen, setChosen] = useState(guru.accounts[0]?.id ?? "")
  // Performance is one account's: the chosen one, or the first when the choice left the setup.
  const accountId = guru.accounts.some((a) => a.id === chosen) ? chosen : (guru.accounts[0]?.id ?? "")
  const performance = useResult(
    () => window.copytrading.read.getGuruPerformance({ account_id: accountId, guru_id: guru.id }),
    `performance:${guru.id}:${accountId}`,
    60_000,
  )

  const dayStats = day.status === "ready" ? day.data.gurus.find((s) => s.guru_id === guru.id) : undefined
  const feed = posts.status === "ready" ? buildFeed(guru.id, posts.items, dayStats, now) : null
  const entries = useMemo(() => feed?.days.flatMap((d) => d.entries) ?? [], [posts.status === "ready" ? posts.items : null, dayStats]) // eslint-disable-line react-hooks/exhaustive-deps
  const opened = entries.find((e) => e.post.sequence === open)?.post
  const holdings = accounts.status === "ready" ? guruHoldings(guru.id, accounts.data.items, setUpAccountIds) : undefined
  const more = posts.status === "ready" && posts.hasOlder

  const account = accounts.status === "ready" ? accounts.data.items.find((a) => a.account_id === accountId) : undefined
  const state = account ? accountCopying(account, status.status === "ready" ? status.data : null) : null
  const copying = state && { title: COPYING_TITLE[state.word], tone: badgeTone(state), detail: state.detail }

  const performed = performance.status === "ready" ? performance.data : null
  const days_ = TREND_RANGES.find((r) => r.value === range)!.days
  // The page re-renders every few seconds; the chart is given a new array only when the series or the range changes.
  const rows = useMemo(() => (performed ? trendRows(performed.series, days_, now) : []), [performed, days_]) // eslint-disable-line react-hooks/exhaustive-deps
  const refresh = () => {
    day.retry()
    if (posts.status === "error") posts.retry()
    status.retry()
    performance.retry()
  }

  return (
    <div className={styles.page}>
      <GuruHeader guru={guru} accountId={accountId} onAccountChange={setChosen} copying={copying} live={guru.accounts.find((a) => a.id === accountId)?.environment === "live"} onRefresh={refresh} />
      {day.status === "error" && <RegionAlert title="Today's numbers did not load" message={day.error} onRetry={day.retry} />}
      <GuruKpis stats={guruStats(dayStats, feed?.waitingCount ?? 0, day.status === "ready" && feed !== null)} performance={performed} holdings={holdings} />
      {accountId && (
        <GuruTrendChart
          rows={rows}
          state={performance.status === "ready" ? { status: "ready" } : performance.status === "error" ? { status: "error", error: performance.error } : { status: "loading" }}
          closedTrades={performed?.closed_trades ?? 0}
          windowed={days_ !== null}
          range={range}
          onRangeChange={setRange}
          onShowAll={() => setRange("all")}
          onRetry={performance.retry}
        />
      )}
      <div className={styles.columns}>
        {/* The posts run long; the breakdown stays in view beside them instead of leaving an empty column. */}
        <div className={styles.sticky}>
          <GuruBreakdown performance={performed} accountId={accountId} error={performance.status === "error" ? performance.error : null} onRetry={performance.retry} />
        </div>
        <GuruActivity guruName={guru.name} now={now} entries={entries} more={more} posts={posts} filter={filter} onFilterChange={setFilter} onOpen={setOpen} />
      </div>

      <GuruPostSheet post={opened} guruName={guru.name} now={now} onClose={() => setOpen(null)} />
    </div>
  )
}
