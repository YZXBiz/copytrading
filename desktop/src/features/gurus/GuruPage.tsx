import { useState } from "react"
import type { AccountOverviewPage } from "../../../shared/contract"
import { RegionError } from "@/components/region-error"
import { accountCopying, badgeVariant, COPYING_TITLE } from "@/features/account/copying"
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
import { type Guru, type PostFilter, TREND_RANGES, type TrendRange, buildFeed, guruHoldings, guruStats, includesEntry, trendRows } from "./model"

/**
 * One guru's page, ReUI's solution-analytics-8 (Metric Deep Dive) filled with this guru: header, four figures, the profit
 * line against break-even, the breakdown beside the posts. A chosen post opens in a sheet.
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
  const opened = feed?.days.flatMap((d) => d.entries).find((e) => e.post.sequence === open)?.post
  const holdings = accounts.status === "ready" ? guruHoldings(guru.id, accounts.data.items, setUpAccountIds) : undefined
  const days = feed ? feed.days.map((d) => ({ ...d, entries: d.entries.filter((e) => includesEntry(filter, e)) })).filter((d) => d.entries.length > 0) : []
  const loaded = feed ? feed.days.reduce((sum, d) => sum + d.entries.length, 0) : 0
  const more = posts.status === "ready" && posts.hasOlder

  const account = accounts.status === "ready" ? accounts.data.items.find((a) => a.account_id === accountId) : undefined
  const state = account ? accountCopying(account, status.status === "ready" ? status.data : null) : null
  const copying = state && { title: COPYING_TITLE[state.word], variant: badgeVariant(state), detail: state.detail }

  const performed = performance.status === "ready" ? performance.data : null
  const days_ = TREND_RANGES.find((r) => r.value === range)!.days
  const rows = performed ? trendRows(performed.series, days_, now) : []
  const refresh = () => {
    day.retry()
    if (posts.status === "error") posts.retry()
    status.retry()
    performance.retry()
  }

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-6">
      <GuruHeader
        guru={guru}
        accountId={accountId}
        onAccountChange={setChosen}
        copying={copying}
        live={guru.accounts.find((a) => a.id === accountId)?.environment === "live"}
        range={range}
        onRangeChange={setRange}
        onRefresh={refresh}
      />
      {day.status === "error" && <RegionError title="Today's numbers did not load" message={day.error} onRetry={day.retry} />}
      <GuruKpis stats={guruStats(dayStats, feed?.waitingCount ?? 0, day.status === "ready" && feed !== null)} performance={performed} holdings={holdings} />
      {accountId && (
        <GuruTrendChart
          rows={rows}
          state={performance.status === "ready" ? { status: "ready" } : performance.status === "error" ? { status: "error", error: performance.error } : { status: "loading" }}
          closedTrades={performed?.closed_trades ?? 0}
          windowed={days_ !== null}
          onShowAll={() => setRange("all")}
          onRetry={performance.retry}
        />
      )}
      <div className="grid grid-cols-1 items-start gap-6 md:grid-cols-2">
        {/* The posts run long; the breakdown stays in view beside them instead of leaving an empty column. */}
        <div className="md:sticky md:top-4">
          <GuruBreakdown performance={performed} error={performance.status === "error" ? performance.error : null} onRetry={performance.retry} />
        </div>
        <GuruActivity guruName={guru.name} now={now} days={days} loaded={loaded} more={more} posts={posts} filter={filter} onFilterChange={setFilter} onOpen={setOpen} />
      </div>

      <GuruPostSheet post={opened} guruName={guru.name} now={now} onClose={() => setOpen(null)} />
    </div>
  )
}
