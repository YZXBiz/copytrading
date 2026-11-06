import { useEffect, useMemo, useState } from "react"
import { Message01Icon } from "@/components/icons/Message01Icon"
import type { AccountOverviewPage } from "../../../shared/contract"
import { Button } from "@/components/arc/button/button"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import { GuruPostSheet } from "@/features/gurus/GuruPostSheet"
import { guruName } from "@/features/gurus/model"
import { useGurus } from "@/features/gurus/use-gurus"
import { navigate } from "@/features/shell/route"
import { readClock } from "@/lib/clock"
import { getTimeZone } from "@/lib/time-zone"
import { type Loaded } from "@/lib/use-result"
import { ActivityHeader } from "./ActivityHeader"
import { ActivityMetrics } from "./ActivityMetrics"
import { ActivitySkeleton } from "./ActivitySkeleton"
import { ActivityPosts, type PostFilter } from "./ActivityTable"
import { type Mix, MixChart } from "./MixChart"
import { PostsChart } from "./PostsChart"
import { RegionAlert } from "./RegionAlert"
import { activityRows, followedPosts } from "./activity-rows"
import { dayCounts, dayKey, dayRows, guruMix, shiftDay, skipReasons } from "./post-bucket"
import { usePosts } from "./use-posts"
import styles from "./activity.module.css"

/** The charts look back this many days; posts are read a page at a time until they reach that far. */
const DAYS = 30
/** A guard on that reading: enough pages for a very busy month, no more. */
const MAX_POSTS = 2000

/** The day's counts and the month's charts over every post newest first, each with its accounts' outcome; the chosen post opens beside them. */
export function ActivityScreen({ selectedSequence, accounts }: { selectedSequence: number | null; accounts: Loaded<AccountOverviewPage> }) {
  const [filter, setFilter] = useState<PostFilter>("all")
  const [accountId, setAccountId] = useState<string | null>(null)
  const posts = usePosts((before_seq, limit) => window.copytrading.read.getSourceActivity({ before_seq, limit }), "activity")
  const { gurus, config } = useGurus()
  const now = readClock()
  const zone = getTimeZone()
  const today = dayKey(now, zone)
  const [chosen, setDay] = useState<string | null>(null)
  const day = chosen ?? today
  const accountIds = accounts.status === "ready" ? accounts.data.items.map((a) => a.account_id) : []
  const nameOf = (id: string | null) => guruName(gurus, id)

  const all = posts.status === "ready" ? posts.items : null
  const oldest = all?.at(-1)
  const items = useMemo(() => (all ? followedPosts(all, config) : null), [all, config])
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
  // While older pages are still being read for the month, the charts would jump with each page: wait for all of them,
  // including while one is in flight (`readBack` is false then, which made the charts flash between pages).
  const monthLoaded = !(posts.status === "ready" && posts.hasOlder && readAll && posts.items.length < MAX_POSTS)

  const open = items?.find((p) => p.sequence === selectedSequence)
  const waiting = counts.total.waiting
  const status = waiting > 0 ? `${waiting} waiting for you` : "Nothing needs you"

  if (posts.status === "loading") return <ActivitySkeleton />
  if (posts.status === "error") return <RegionAlert title="Posts did not load" message={posts.error} onRetry={posts.retry} />
  if (items!.length === 0) {
    return (
      <div className={styles.page}>
        <EmptyState
          icon={<Message01Icon width={24} height={24} aria-hidden="true" />}
          title="No posts yet"
          description="Posts from the gurus you copy appear here as they arrive."
          action={
            <Button variant="secondary" size="sm" onClick={() => navigate("settings", "connections")}>
              Open Connections
            </Button>
          }
        />
      </div>
    )
  }

  return (
    <section className={styles.page} aria-labelledby="activity-title">
      <ActivityHeader day={day} today={today} status={status} onDayChange={setDay} />
      <ActivityMetrics today={counts} before={before} />
      <div className={styles.charts}>
        {monthLoaded ? <PostsChart rows={postsPerDay} /> : <Skeleton label="Reading the month" lines={5} className={styles.tall} />}
        {monthLoaded ? <MixChart mix={mix} /> : <Skeleton label="Reading the month" lines={5} className={styles.tall} />}
      </div>
      <ActivityPosts
        rows={rows}
        now={now}
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
