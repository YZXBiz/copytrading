import { useState } from "react"
import { MessageSquareIcon } from "lucide-react"
import type { AccountOverviewPage } from "../../../shared/contract"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Empty, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { Frame, FramePanel } from "@/components/reui/frame"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { Spinner } from "@/components/ui/spinner"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { PostListSkeleton } from "@/features/activity/PostList"
import { PostView } from "@/features/activity/PostView"
import { usePosts } from "@/features/activity/use-posts"
import { dayWindow } from "@/features/activity/time"
import { readClock } from "@/lib/clock"
import { type Loaded, useResult } from "@/lib/use-result"
import { GuruDestinations } from "./GuruDestinations"
import { GuruHoldingsLine } from "./GuruHoldingsLine"
import { GuruStats } from "./GuruStats"
import { GuruTimeline } from "./GuruTimeline"
import { POST_FILTERS, type PostFilter, buildFeed, guruHoldings, guruStats, includesEntry, type Guru } from "./model"

/** One guru's page: where their calls go, today's numbers, what is held from them, and every post they made, newest first. A chosen post opens beside the page. */
export function GuruPage({ guru, accounts, setUpAccountIds }: { guru: Guru; accounts: Loaded<AccountOverviewPage>; setUpAccountIds: Set<string> }) {
  const now = readClock()
  const window_ = dayWindow(now)
  const day = useResult(() => window.copytrading.read.getGuruDayStats(window_), `day:${guru.id}:${window_.day_start}`)
  const posts = usePosts((before_seq, limit) => window.copytrading.read.getGuruActivity({ guru_id: guru.id, before_seq, limit }), `guru:${guru.id}`)
  const [filter, setFilter] = useState<PostFilter>("all")
  const [open, setOpen] = useState<number | null>(null)

  const dayStats = day.status === "ready" ? day.data.items.find((s) => s.guru_id === guru.id) : undefined
  const feed = posts.status === "ready" ? buildFeed(guru.id, posts.items, dayStats, now) : null
  const opened = feed?.days.flatMap((d) => d.entries).find((e) => e.post.sequence === open)?.post
  const holdings = accounts.status === "ready" ? guruHoldings(guru.id, accounts.data.items, setUpAccountIds) : null

  return (
    <div className="flex max-w-4xl flex-col gap-6">
      <header className="flex flex-col gap-1">
        <h2 className="text-2xl font-semibold tracking-tight">{guru.name}</h2>
        <GuruDestinations guru={guru} />
      </header>
      {day.status === "error" ? (
        <RegionError title="Today's numbers did not load" message={day.error} onRetry={day.retry} />
      ) : (
        <GuruStats stats={guruStats(dayStats, feed?.waitingCount ?? 0, day.status === "ready" && feed !== null)} />
      )}
      <GuruHoldingsLine holdings={holdings} />
      <Frame spacing="sm">
        <FramePanel>
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h3 className="font-medium">Posts</h3>
            <ToggleGroup aria-label="Filter posts" variant="outline" size="sm" spacing={0} value={[filter]} onValueChange={(next) => next[0] && setFilter(next[0] as PostFilter)}>
              {POST_FILTERS.map(({ id, label }) => (
                <ToggleGroupItem key={id} value={id}>
                  {label}
                </ToggleGroupItem>
              ))}
            </ToggleGroup>
          </div>
          {posts.status === "loading" && <PostListSkeleton />}
          {posts.status === "error" && <RegionError title="Posts did not load" message={posts.error} onRetry={posts.retry} />}
          {feed && <Timeline feed={feed} filter={filter} onOpen={setOpen} older={posts} />}
        </FramePanel>
      </Frame>
      <Sheet open={opened !== undefined} onOpenChange={(next) => !next && setOpen(null)}>
        <SheetContent className="flex flex-col gap-0 space-y-0 sm:max-w-xl">
          <SheetHeader>
            <SheetTitle>{guru.name}</SheetTitle>
            <SheetDescription className="sr-only">The post in full, and what each account did.</SheetDescription>
          </SheetHeader>
          <ScrollArea className="min-h-0 flex-1">
            <div className="px-4 pb-6">{opened && <PostView post={opened} guruName={guru.name} now={now} />}</div>
          </ScrollArea>
        </SheetContent>
      </Sheet>
    </div>
  )
}

function Timeline({ feed, filter, onOpen, older }: { feed: ReturnType<typeof buildFeed>; filter: PostFilter; onOpen: (sequence: number) => void; older: ReturnType<typeof usePosts> }) {
  const days = feed.days.map((d) => ({ ...d, entries: d.entries.filter((e) => includesEntry(filter, e)) })).filter((d) => d.entries.length > 0)
  const more = older.status === "ready" && older.hasOlder
  return (
    <>
      {days.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <MessageSquareIcon />
            </EmptyMedia>
            <EmptyTitle>{filter === "all" ? "No posts yet" : "No posts match"}</EmptyTitle>
            <EmptyDescription>{more ? "Show older to look further back." : "Posts from this guru appear here as they arrive."}</EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        <GuruTimeline days={days} onOpen={onOpen} />
      )}
      {older.status === "ready" && more && (
        <div className="mt-4 flex flex-col items-center gap-2">
          {typeof older.older === "object" && <RegionError title="Older posts did not load" message={older.older.error} onRetry={older.showOlder} />}
          {typeof older.older !== "object" && (
            <Button type="button" size="sm" variant="outline" onClick={older.showOlder} disabled={older.older === "loading"}>
              {older.older === "loading" && <Spinner data-icon="inline-start" />}
              Show older
            </Button>
          )}
        </div>
      )}
    </>
  )
}
