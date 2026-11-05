import { useState } from "react"
import { FilterIcon, MessageSquareIcon } from "lucide-react"
import type { AccountOverviewPage } from "../../../shared/contract"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { EmptyState } from "@/components/empty-state"
import { navigate } from "@/features/shell/route"
import { Spinner } from "@/components/ui/spinner"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { PostsSkeleton } from "@/features/activity/PostsSkeleton"
import { usePosts } from "@/features/activity/use-posts"
import { dayWindow } from "@/features/activity/time"
import { readClock } from "@/lib/clock"
import { type Loaded, useResult } from "@/lib/use-result"
import { GuruDestinations } from "./GuruDestinations"
import { GuruPerformanceCard } from "./GuruPerformanceCard"
import { GuruPostSheet } from "./GuruPostSheet"
import { GuruStats } from "./GuruStats"
import { GuruTimeline } from "./GuruTimeline"
import { POST_FILTERS, type PostFilter, buildFeed, guruHoldings, guruStats, includesEntry, type Guru } from "./model"

/** One guru's page: where their calls go, today's numbers, what is held from them, and every post they made, newest first. A chosen post opens in a sheet. */
export function GuruPage({ guru, accounts, setUpAccountIds }: { guru: Guru; accounts: Loaded<AccountOverviewPage>; setUpAccountIds: Set<string> }) {
  const now = readClock()
  const window_ = dayWindow(now)
  const day = useResult(() => window.copytrading.read.getGuruDayStats(window_), `day:${guru.id}:${window_.day_start}`, 30_000)
  const posts = usePosts((before_seq, limit) => window.copytrading.read.getGuruActivity({ guru_id: guru.id, before_seq, limit }), `guru:${guru.id}`)
  const [filter, setFilter] = useState<PostFilter>("all")
  const [open, setOpen] = useState<number | null>(null)

  const dayStats = day.status === "ready" ? day.data.gurus.find((s) => s.guru_id === guru.id) : undefined
  const feed = posts.status === "ready" ? buildFeed(guru.id, posts.items, dayStats, now) : null
  const opened = feed?.days.flatMap((d) => d.entries).find((e) => e.post.sequence === open)?.post
  const holdings = accounts.status === "ready" ? guruHoldings(guru.id, accounts.data.items, setUpAccountIds) : null
  const days = feed ? feed.days.map((d) => ({ ...d, entries: d.entries.filter((e) => includesEntry(filter, e)) })).filter((d) => d.entries.length > 0) : []
  const loaded = feed ? feed.days.reduce((sum, d) => sum + d.entries.length, 0) : 0
  const more = posts.status === "ready" && posts.hasOlder

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-wrap items-center gap-x-3 gap-y-1">
        <h2 className="text-2xl font-semibold tracking-tight">{guru.name}</h2>
        <GuruDestinations guru={guru} />
      </header>
      {day.status === "error" ? (
        <RegionError title="Today's numbers did not load" message={day.error} onRetry={day.retry} />
      ) : (
        <GuruStats stats={guruStats(dayStats, feed?.waitingCount ?? 0, day.status === "ready" && feed !== null)} holdings={holdings} />
      )}

      <GuruPerformanceCard guru={guru} />

      <section className="w-full" aria-labelledby="guru-posts-title">
        {/* Content header (title + filter tabs) */}
        <div className="mb-5 flex flex-col gap-4">
          <div className="space-y-0.5">
            <h3 id="guru-posts-title" className="text-base font-semibold">
              Posts
            </h3>
            {feed && (
              <p className="text-muted-foreground text-sm leading-5">
                {loaded}
                {more ? "+" : ""} {loaded === 1 ? "post" : "posts"}, newest first
              </p>
            )}
          </div>
          <Tabs value={filter} onValueChange={(value) => value && setFilter(value as PostFilter)}>
            <TabsList variant="line" aria-label="Filter posts" className="h-10! w-full justify-start gap-6 overflow-x-auto border-b pb-0">
              {POST_FILTERS.map(({ id, label }) => (
                <TabsTrigger key={id} value={id} className="px-1 text-sm after:-bottom-px!">
                  {label}
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
        </div>

        {posts.status === "loading" && <PostsSkeleton />}
        {posts.status === "error" && <RegionError title="Posts did not load" message={posts.error} onRetry={posts.retry} />}
        {feed && days.length === 0 && (
          <EmptyState
            icon={filter === "all" ? MessageSquareIcon : FilterIcon}
            title={filter === "all" ? "No posts yet" : "No posts match"}
            description={more ? "Show older to look further back." : "Posts from this guru appear here as they arrive."}
            action={more ? undefined : filter === "all" ? { label: "Open Connections", onClick: () => navigate("settings", "connections") } : { label: "Clear filter", onClick: () => setFilter("all") }}
          />
        )}
        {days.length > 0 && <GuruTimeline days={days} guruName={guru.name} now={now} onOpen={setOpen} />}
        {posts.status === "ready" && more && (
          <div className="mt-8 flex flex-col items-center gap-2">
            {typeof posts.older === "object" && <RegionError title="Older posts did not load" message={posts.older.error} onRetry={posts.showOlder} />}
            {typeof posts.older !== "object" && (
              <Button type="button" size="sm" variant="outline" onClick={posts.showOlder} disabled={posts.older === "loading"}>
                {posts.older === "loading" && <Spinner data-icon="inline-start" />}
                Show older
              </Button>
            )}
          </div>
        )}
      </section>

      <GuruPostSheet post={opened} guruName={guru.name} now={now} onClose={() => setOpen(null)} />
    </div>
  )
}
