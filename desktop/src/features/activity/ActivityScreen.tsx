import { useState } from "react"
import type { AccountOverviewPage } from "../../../shared/contract"
import { Frame, FramePanel } from "@/components/reui/frame"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { guruName } from "@/features/gurus/model"
import { useGurus } from "@/features/gurus/use-gurus"
import { readClock } from "@/lib/clock"
import { cn } from "@/lib/utils"
import { type Loaded } from "@/lib/use-result"
import { PostList, PostListSkeleton } from "./PostList"
import { PostView } from "./PostView"
import { type ActivityFilter, FILTERS, includes, reachedAccount } from "./outcome"
import { usePosts } from "./use-posts"

const EMPTY: Record<ActivityFilter, { title: string; hint: string }> = {
  all: { title: "No posts yet", hint: "Posts from the gurus you copy appear here as they arrive." },
  waiting: { title: "Nothing needs you", hint: "A post that waits for you shows here until its trading day ends." },
  traded: { title: "Nothing traded in these posts", hint: "Posts an account bought or sold on show here." },
}

/** Every post newest first with each account's outcome, filtered; the chosen post opens beside the list. */
export function ActivityScreen({ selectedSequence, accounts }: { selectedSequence: number | null; accounts: Loaded<AccountOverviewPage> }) {
  const [filter, setFilter] = useState<ActivityFilter>("all")
  const [accountId, setAccountId] = useState<string | null>(null)
  const posts = usePosts((before_seq, limit) => window.copytrading.read.getSourceActivity({ before_seq, limit }), "activity")
  const { gurus } = useGurus()
  const now = readClock()
  const accountIds = accounts.status === "ready" ? accounts.data.items.map((a) => a.account_id) : []

  const shown = posts.status === "ready" ? posts.items.filter((p) => reachedAccount(p, accountId) && includes(filter, p, now)) : []
  // The chosen post, or the newest one that shows: a post filtered away is never left open.
  const selected = shown.find((p) => p.sequence === selectedSequence) ?? shown[0]
  const choices = [{ value: "all", label: "All accounts" }, ...accountIds.map((id) => ({ value: id, label: id }))]

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <ToggleGroup
          aria-label="Filter posts"
          variant="outline"
          size="sm"
          spacing={0}
          value={[filter]}
          onValueChange={(next) => next[0] && setFilter(next[0] as ActivityFilter)}
        >
          {FILTERS.map(({ id, label }) => (
            <ToggleGroupItem key={id} value={id}>
              {label}
            </ToggleGroupItem>
          ))}
        </ToggleGroup>
        {accountIds.length > 1 && (
          <Select items={choices} value={accountId ?? "all"} onValueChange={(next) => setAccountId(next === "all" ? null : next)}>
            <SelectTrigger size="sm" aria-label="Account">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {choices.map((choice) => (
                <SelectItem key={choice.value} value={choice.value}>
                  {choice.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        )}
      </div>
      <div className={cn("grid items-start gap-4", (posts.status === "loading" || selected) && "lg:grid-cols-[minmax(0,26rem)_minmax(0,1fr)]")}>
        <Frame spacing="sm" dense>
          <FramePanel className="p-0">
            <PostList
              posts={posts}
              shown={shown}
              selected={selected?.sequence}
              guruName={(id) => guruName(gurus, id)}
              now={now}
              emptyTitle={EMPTY[filter].title}
              emptyHint={EMPTY[filter].hint}
            />
          </FramePanel>
        </Frame>
        {(posts.status === "loading" || selected) && (
          <Frame spacing="sm" className="lg:sticky lg:top-0">
            <FramePanel>
              {selected ? <PostView post={selected} guruName={guruName(gurus, selected.guru_id)} now={now} accountId={accountId} /> : <PostListSkeleton />}
            </FramePanel>
          </Frame>
        )}
      </div>
    </div>
  )
}
