// ReUI's Audit Log (solution-users-6), installed as shipped and wired to the guru posts: the header with its subtitle and
// select, the line tabs, a heading and a timeline per day, and its empty state. The block's Export CSV has nothing behind it here.
import { useState } from "react"
import { FilterIcon, LandmarkIcon, MessageSquareIcon } from "lucide-react"
import type { AccountOverviewPage } from "../../../shared/contract"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Spinner } from "@/components/ui/spinner"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { guruName } from "@/features/gurus/model"
import { useGurus } from "@/features/gurus/use-gurus"
import { readClock } from "@/lib/clock"
import { type Loaded } from "@/lib/use-result"
import { ActivityDay } from "./ActivityEvent"
import { PostsSkeleton } from "./PostsSkeleton"
import { type ActivityFilter, FILTERS, includes, reachedAccount } from "./outcome"
import { groupByDay } from "./time"
import { usePosts } from "./use-posts"

const EMPTY: Record<ActivityFilter, { title: string; hint: string }> = {
  all: { title: "No posts yet", hint: "Posts from the gurus you copy appear here as they arrive." },
  waiting: { title: "Nothing needs you", hint: "A post that waits for you shows here until its trading day ends." },
  traded: { title: "Nothing traded in these posts", hint: "Posts an account bought or sold on show here." },
}

/** Every post newest first, a timeline for each day, with each account's outcome; the chosen post opens in place. */
export function ActivityScreen({ selectedSequence, accounts }: { selectedSequence: number | null; accounts: Loaded<AccountOverviewPage> }) {
  const [filter, setFilter] = useState<ActivityFilter>("all")
  const [accountId, setAccountId] = useState<string | null>(null)
  const posts = usePosts((before_seq, limit) => window.copytrading.read.getSourceActivity({ before_seq, limit }), "activity")
  const { gurus } = useGurus()
  const now = readClock()
  const accountIds = accounts.status === "ready" ? accounts.data.items.map((a) => a.account_id) : []
  const choices = [{ value: "all", label: "All accounts" }, ...accountIds.map((id) => ({ value: id, label: id }))]

  const shown = posts.status === "ready" ? posts.items.filter((p) => reachedAccount(p, accountId) && includes(filter, p, now)) : []
  // The chosen post, or the newest one that shows: a post filtered away is never left open.
  const openSequence = (shown.find((p) => p.sequence === selectedSequence) ?? shown[0])?.sequence
  const filtered = filter !== "all" || accountId !== null

  return (
    <section className="w-full" aria-labelledby="activity-title">
      {/* Content header (title + account + filter tabs) */}
      <div className="mb-6 flex flex-col gap-4">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div className="min-w-0 space-y-1">
            <h1 id="activity-title" className="text-xl font-semibold tracking-tight">
              Guru posts
            </h1>
            {posts.status === "ready" && (
              <p className="text-muted-foreground text-sm leading-5">
                {posts.items.length}
                {posts.hasOlder ? "+" : ""} {posts.items.length === 1 ? "post" : "posts"} from the gurus you copy
              </p>
            )}
          </div>

          {accountIds.length > 1 && (
            <div className="flex shrink-0 items-center gap-2">
              <Select items={choices} value={accountId ?? "all"} onValueChange={(next) => next && setAccountId(next === "all" ? null : next)}>
                <SelectTrigger size="sm" className="w-44" aria-label="Account">
                  <LandmarkIcon className="text-muted-foreground size-4" aria-hidden="true" />
                  <SelectValue />
                </SelectTrigger>
                <SelectContent align="end" alignItemWithTrigger={false}>
                  <SelectGroup>
                    {choices.map((choice) => (
                      <SelectItem key={choice.value} value={choice.value}>
                        {choice.label}
                      </SelectItem>
                    ))}
                  </SelectGroup>
                </SelectContent>
              </Select>
            </div>
          )}
        </div>

        <Tabs value={filter} onValueChange={(value) => value && setFilter(value as ActivityFilter)}>
          <TabsList variant="line" aria-label="Filter posts" className="h-10! w-full justify-start gap-6 overflow-x-auto border-b pb-0">
            {FILTERS.map(({ id, label }) => (
              <TabsTrigger key={id} value={id} className="px-1 text-sm after:-bottom-px!">
                {label}
              </TabsTrigger>
            ))}
          </TabsList>
        </Tabs>
      </div>

      {posts.status === "loading" && <PostsSkeleton />}
      {posts.status === "error" && <RegionError title="Posts did not load" message={posts.error} onRetry={posts.retry} />}
      {posts.status === "ready" && shown.length === 0 && (
        <Empty className="min-h-[280px] border-0 bg-transparent">
          <EmptyHeader>
            <EmptyMedia variant="icon">{filtered ? <FilterIcon aria-hidden="true" /> : <MessageSquareIcon aria-hidden="true" />}</EmptyMedia>
            <EmptyTitle>{EMPTY[filter].title}</EmptyTitle>
            <EmptyDescription>{posts.hasOlder ? "Show older to look further back." : EMPTY[filter].hint}</EmptyDescription>
          </EmptyHeader>
          {filtered && (
            <EmptyContent>
              <Button
                type="button"
                variant="outline"
                onClick={() => {
                  setFilter("all")
                  setAccountId(null)
                }}
              >
                Clear filter
              </Button>
            </EmptyContent>
          )}
        </Empty>
      )}
      {shown.length > 0 && (
        <div className="space-y-8">
          {groupByDay(shown, (post) => post.source_at, now).map(({ label, items }) => (
            <div key={label} className="space-y-4">
              <h2 className="text-muted-foreground text-xs font-semibold tracking-wide uppercase">{label}</h2>
              <ActivityDay posts={items} openSequence={openSequence} guruName={(id) => guruName(gurus, id)} now={now} accountId={accountId} />
            </div>
          ))}
        </div>
      )}
      {posts.status === "ready" && posts.hasOlder && (
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
  )
}
