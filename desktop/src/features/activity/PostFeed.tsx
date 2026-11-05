import { useMemo, type ReactNode } from "react"
import type { SourceActivity } from "../../../shared/contract"
import { ActivityFeed, type FeedFilter, type FeedItem } from "@/components/arc/blocks/activity-feed/activity-feed"
import { postSymbol, type GuruAccountOutcome } from "@/features/gurus/model"
import { OutcomeBadge } from "./OutcomeBadge"
import { PostImage } from "./PostImage"
import { PostMark } from "./PostMark"
import { PostTickers, postTickers } from "./PostTickers"
import { cardOutcome } from "./outcome"
import { pictureOf, readableText } from "./reading"
import { clockTime, dayLabel } from "./time"

/** One post as a feed row needs it: who said it, how it was read, what each account did, and which filters keep it. */
export interface PostFeedEntry {
  post: SourceActivity
  guru: string
  readAs: string
  accounts: GuruAccountOutcome[]
  /** The filter values, besides the first, that keep this post. */
  kinds: string[]
}

function feedItem({ post, guru, readAs, accounts, kinds }: PostFeedEntry, now: Date): FeedItem {
  const outcome = cardOutcome(post, now)
  // A post with no words of its own shows its picture.
  const picture = pictureOf(post)
  const said = readableText(post)
  // A post that was only chat has nothing to add to its badge.
  const detail = post.decision !== "ignore" && !(post.decision === "review" && post.instructions.length === 0)
  const label = dayLabel(post.source_at, now)
  const date = new Date(post.source_at).toLocaleDateString("en-US", { month: "short", day: "numeric" })
  return {
    id: String(post.sequence),
    order: post.sequence,
    kinds,
    dayKey: new Date(post.source_at).toDateString(),
    dayTitle: label.includes(",") ? label.split(",")[0]! : label,
    dayDate: date,
    actor: guru,
    action: picture ? "posted a picture" : said ? "posted" : "posted no words",
    quote: said || undefined,
    thumb: picture ? <PostImage attachment={picture} compact /> : undefined,
    meta: (
      <>
        <OutcomeBadge title={outcome.title} tone={outcome.tone} />
        {detail && <span>{readAs}</span>}
      </>
    ),
    lines: accounts.map((account) => (
      <>
        <strong>{account.accountId}</strong> {account.summary}
      </>
    )),
    mark: <PostMark symbol={postSymbol(post)} />,
    tickers: postTickers(post).length > 0 ? <PostTickers post={post} /> : undefined,
    time: clockTime(post.source_at),
    datetime: post.source_at,
  }
}

/** Posts as the day-by-day feed, newest first: the filter and the new-posts button are the feed's, the rows and the older pages are the screen's. */
export function PostFeed({
  entries,
  now,
  filters,
  filter,
  onFilterChange,
  onOpen,
  resetKey,
  older,
  empty,
  tools,
  title,
}: {
  entries: PostFeedEntry[]
  now: Date
  filters: FeedFilter[]
  filter: string
  onFilterChange: (value: string) => void
  onOpen: (sequence: number) => void
  resetKey: string
  older?: { loading: boolean; error?: string; show: () => void } | null
  empty: ReactNode
  tools?: ReactNode
  title?: string
}) {
  // The screen re-renders every few seconds with a fresh clock; rows are rebuilt only when the posts change.
  const items = useMemo(() => entries.map((entry) => feedItem(entry, now)), [entries]) // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <ActivityFeed
      items={items}
      filters={filters}
      filter={filter}
      onFilterChange={onFilterChange}
      onOpen={(id) => onOpen(Number(id))}
      resetKey={resetKey}
      older={older}
      empty={empty}
      tools={tools}
      title={title}
    />
  )
}
