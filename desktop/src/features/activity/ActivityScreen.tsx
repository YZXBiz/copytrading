// ReUI's dashboard-7 (Retail Revenue) as one page: its header with a date picker, four KPI cards with a sparkline each, the
// stacked area chart beside the bar chart, and the order queue's DataGrid, filled with the guru posts. A row opens the post.
import { useEffect, useMemo, useState } from "react"
import { Message01Icon } from "@/components/icons/Message01Icon"
import type { AccountOverviewPage } from "../../../shared/contract"
import { EmptyState } from "@/components/empty-state"
import { RegionError } from "@/components/region-error"
import { GuruPostSheet } from "@/features/gurus/GuruPostSheet"
import { guruName } from "@/features/gurus/model"
import { useGurus } from "@/features/gurus/use-gurus"
import { navigate } from "@/features/shell/route"
import { readClock } from "@/lib/clock"
import { getTimeZone } from "@/lib/time-zone"
import { type Loaded } from "@/lib/use-result"
import { ActivityHeader } from "./ActivityHeader"
import { ActivityMetrics } from "./ActivityMetrics"
import { Skeleton } from "@/components/ui/skeleton"
import { ActivitySkeleton } from "./ActivitySkeleton"
import { ActivityTable, type PostFilter } from "./ActivityTable"
import { type Mix, MixChart } from "./MixChart"
import { PostsChart } from "./PostsChart"
import { activityRows } from "./activity-rows"
import { dayCounts, dayKey, dayRows, guruMix, shiftDay, skipReasons } from "./post-bucket"
import { usePosts } from "./use-posts"

/** The charts look back this many days; posts are read a page at a time until they reach that far. */
const DAYS = 30
/** A guard on that reading: enough pages for a very busy month, no more. */
const MAX_POSTS = 2000

/** Every post newest first as a table under the day's counts and the month's charts, with each account's outcome; the chosen post opens beside it. */
export function ActivityScreen({ selectedSequence, accounts }: { selectedSequence: number | null; accounts: Loaded<AccountOverviewPage> }) {
  const [filter, setFilter] = useState<PostFilter>("all")
  const [accountId, setAccountId] = useState<string | null>(null)
  const posts = usePosts((before_seq, limit) => window.copytrading.read.getSourceActivity({ before_seq, limit }), "activity")
  const { gurus } = useGurus()
  const now = readClock()
  const zone = getTimeZone()
  const today = dayKey(now, zone)
  const [chosen, setDay] = useState<string | null>(null)
  const day = chosen ?? today
  const accountIds = accounts.status === "ready" ? accounts.data.items.map((a) => a.account_id) : []
  const nameOf = (id: string | null) => guruName(gurus, id)

  const items = posts.status === "ready" ? posts.items : null
  const oldest = items?.at(-1)
  const [readBack, readAll] = [posts.status === "ready" && posts.hasOlder && posts.older === "idle", oldest !== undefined && dayKey(new Date(oldest.source_at), zone) > shiftDay(today, 1 - DAYS)]
  // The charts need the whole month: keep reading older pages until the oldest post is past it.
  useEffect(() => {
    if (posts.status === "ready" && readBack && readAll && posts.items.length < MAX_POSTS) posts.showOlder()
  }, [posts, readBack, readAll])

  const month = useMemo(() => (items ?? []).filter((p) => dayKey(new Date(p.source_at), zone) >= shiftDay(today, 1 - DAYS)), [items, zone, today])
  const rows = useMemo(() => activityRows(items ?? [], now, nameOf, accountId), [items, accountId, gurus]) // eslint-disable-line react-hooks/exhaustive-deps
  // Chart and card data change only with the posts, the day or the zone: the screen re-renders every few seconds
  // (the accounts refresh), and a fresh array would make every chart animate again.
  const counts = useMemo(() => dayCounts(items ?? [], day, zone, now), [items, day, zone]) // eslint-disable-line react-hooks/exhaustive-deps
  const before = useMemo(() => dayCounts(items ?? [], shiftDay(day, -1), zone, now), [items, day, zone]) // eslint-disable-line react-hooks/exhaustive-deps
  const mix: Mix = useMemo(() => (gurus.length > 1 ? { kind: "gurus", rows: guruMix(month, now, nameOf) } : { kind: "reasons", rows: skipReasons(month, now) }), [month, gurus]) // eslint-disable-line react-hooks/exhaustive-deps
  const postsPerDay = useMemo(() => (items ? dayRows(items, today, zone, now, DAYS) : []), [items, today, zone]) // eslint-disable-line react-hooks/exhaustive-deps
  // While older pages are still being read for the month, the charts would jump with each page: wait for all of them.
  const monthLoaded = !(readBack && readAll && (items?.length ?? 0) < MAX_POSTS)

  const open = items?.find((p) => p.sequence === selectedSequence)
  const waiting = counts.total.waiting
  const status = waiting > 0 ? `${waiting} waiting for you` : "Nothing needs you"

  if (posts.status === "loading") return <ActivitySkeleton />
  if (posts.status === "error") return <RegionError title="Posts did not load" message={posts.error} onRetry={posts.retry} />
  if (posts.items.length === 0) {
    return (
      <div className="mx-auto w-full max-w-7xl">
        <EmptyState
          icon={Message01Icon}
          title="No posts yet"
          description="Posts from the gurus you copy appear here as they arrive."
          action={{ label: "Open Connections", onClick: () => navigate("settings", "connections") }}
        />
      </div>
    )
  }

  return (
    <section className="mx-auto flex w-full max-w-7xl flex-col gap-4" aria-labelledby="activity-title">
      <ActivityHeader day={day} today={today} status={status} onDayChange={setDay} />
      <ActivityMetrics today={counts} before={before} />
      <div className="grid min-w-0 gap-3 lg:grid-cols-[minmax(0,1.5fr)_minmax(300px,1fr)]">
        {monthLoaded ? <PostsChart rows={postsPerDay} /> : <Skeleton className="h-full min-h-72" />}
        {monthLoaded ? <MixChart mix={mix} /> : <Skeleton className="h-full min-h-72" />}
      </div>
      <ActivityTable
        rows={rows}
        accountIds={accountIds}
        accountId={accountId}
        onAccountChange={setAccountId}
        filter={filter}
        onFilterChange={setFilter}
        older={posts.hasOlder && !(readBack && readAll) ? { loading: posts.older === "loading", show: posts.showOlder } : null}
      />
      <GuruPostSheet post={open} guruName={open ? nameOf(open.guru_id) : ""} now={now} onClose={() => navigate("activity")} />
    </section>
  )
}
