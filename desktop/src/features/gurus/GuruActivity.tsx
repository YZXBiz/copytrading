// solution-analytics-8's changes timeline (MetricActivity), as shipped: a Frame with a title and description over a vertical
// Timeline, each row a node on the rail, a title with its time, a detail line and a footer. Changed from the block: the rows are
// the guru's posts with their status badge and time, grouped by day, under the All/Traded/Waiting/Not traded filter. Every node is
// the same bordered tile, holding the stock's logo inset or a neutral icon, centred on one unbroken rail.
import { FilterIcon, MessageSquareIcon } from "lucide-react"
import { RegionError } from "@/components/region-error"
import { EmptyState } from "@/components/empty-state"
import { Frame, FrameDescription, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { Timeline, TimelineContent, TimelineHeader, TimelineIndicator, TimelineItem, TimelineSeparator, TimelineTitle } from "@/components/reui/timeline"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { OutcomeBadge } from "@/features/activity/OutcomeBadge"
import { PostPicture } from "@/features/activity/PostPicture"
import { PostsSkeleton } from "@/features/activity/PostsSkeleton"
import type { Posts } from "@/features/activity/use-posts"
import { cardOutcome } from "@/features/activity/outcome"
import { pictureOf, readableText } from "@/features/activity/reading"
import { clockTime } from "@/features/activity/time"
import { navigate } from "@/features/shell/route"
import { type Day, type Entry, POST_FILTERS, type PostFilter, postSymbol } from "./model"

/** Tickers the logo cache can fetch; anything else gets the letter. */
const HAS_LOGO = /^[A-Z][A-Z0-9.]{0,9}$/

/** The node: one 28 px bordered tile for every post. The logo sits inset with padding, never full-bleed; a post with no stock has a neutral icon in the same tile. */
function Node({ symbol }: { symbol: string | null }) {
  const ticker = symbol?.toUpperCase() ?? null
  return (
    <TimelineIndicator className="bg-background text-muted-foreground flex size-7 items-center justify-center rounded-full border group-data-completed/timeline-item:border-border group-data-[orientation=vertical]/timeline:-top-1 group-data-[orientation=vertical]/timeline:-left-5 [&_svg]:size-3.5">
      {ticker ? (
        <Avatar className="size-[18px] after:hidden">
          {HAS_LOGO.test(ticker) && <AvatarImage src={`ct-logo://${ticker}`} alt="" className="rounded-none object-contain" />}
          <AvatarFallback className="bg-transparent text-[10px] font-medium">{ticker.charAt(0)}</AvatarFallback>
        </Avatar>
      ) : (
        <MessageSquareIcon />
      )}
    </TimelineIndicator>
  )
}

function PostRow({ entry, guruName, now, step, onOpen }: { entry: Entry; guruName: string; now: Date; step: number; onOpen: (sequence: number) => void }) {
  const { post } = entry
  const outcome = cardOutcome(post, now)
  // A post with no words of its own shows its picture.
  const picture = pictureOf(post)
  const said = readableText(post)
  // A post that was only chat has nothing to add to its badge.
  const detail = post.decision !== "ignore" && !(post.decision === "review" && post.instructions.length === 0)
  return (
    <TimelineItem step={step} className="has-[+[data-completed]]:[&_[data-slot=timeline-separator]]:bg-border group-data-[orientation=vertical]/timeline:ms-10 group-data-[orientation=vertical]/timeline:not-last:pb-6">
      <TimelineHeader className="flex min-w-0 items-start justify-between gap-2.5">
        {/* From the node's lower edge to the next node's upper edge, with no gap. */}
        <TimelineSeparator className="bg-border group-data-[orientation=vertical]/timeline:-left-5 group-data-[orientation=vertical]/timeline:h-[calc(100%-1.75rem)] group-data-[orientation=vertical]/timeline:translate-y-6" />
        <Node symbol={postSymbol(post)} />

        <TimelineTitle className="min-w-0 text-sm leading-5">
          <span className="text-foreground font-medium">{guruName}</span> <span className="text-muted-foreground font-normal">{picture ? "posted a picture" : said ? "posted" : "posted no words"}</span>
        </TimelineTitle>

        <time dateTime={post.source_at} className="text-muted-foreground shrink-0 text-xs tabular-nums">
          {clockTime(post.source_at)}
        </time>
      </TimelineHeader>

      <TimelineContent className="flex min-w-0 flex-col items-start gap-2 pb-1">
        {said && <p className="text-foreground line-clamp-2 max-w-[52ch] text-sm leading-5 break-words">“{said}”</p>}
        {detail && <p className="text-muted-foreground max-w-[52ch] text-sm leading-5">{entry.readAs}</p>}
        {entry.accounts.map((account) => (
          <p key={account.accountId} className="text-muted-foreground max-w-[52ch] text-sm leading-5">
            <span className="text-foreground font-medium">{account.accountId}</span> {account.summary}
          </p>
        ))}
        {picture && <PostPicture attachment={picture} className="max-h-32" />}
        <div className="flex flex-wrap items-center gap-2">
          <OutcomeBadge title={outcome.title} tone={outcome.tone} />
          <Button type="button" size="xs" variant="outline" data-sequence={post.sequence} onClick={() => onOpen(post.sequence)}>
            View post
          </Button>
        </div>
      </TimelineContent>
    </TimelineItem>
  )
}

export function GuruActivity({
  guruName,
  now,
  days,
  loaded,
  more,
  posts,
  filter,
  onFilterChange,
  onOpen,
}: {
  guruName: string
  now: Date
  /** The days of the loaded posts that pass the filter. */
  days: Day[]
  /** How many posts are loaded, before the filter. */
  loaded: number
  more: boolean
  posts: Posts
  filter: PostFilter
  onFilterChange: (filter: PostFilter) => void
  onOpen: (sequence: number) => void
}) {
  return (
    <Frame className="h-full">
      <FrameHeader className="gap-3">
        <div className="flex flex-col gap-1">
          <FrameTitle>Posts</FrameTitle>
          <FrameDescription>
            {posts.status === "ready" ? `${loaded}${more ? "+" : ""} ${loaded === 1 ? "post" : "posts"}, newest first` : "Every post this guru made"}
          </FrameDescription>
        </div>
        <Tabs value={filter} onValueChange={(value) => value && onFilterChange(value as PostFilter)}>
          <TabsList aria-label="Filter posts">
            {POST_FILTERS.map(({ id, label }) => (
              <TabsTrigger key={id} value={id}>
                {label}
              </TabsTrigger>
            ))}
          </TabsList>
        </Tabs>
      </FrameHeader>
      <FramePanel>
        {posts.status === "loading" && <PostsSkeleton />}
        {posts.status === "error" && <RegionError title="Posts did not load" message={posts.error} onRetry={posts.retry} />}
        {posts.status === "ready" && days.length === 0 && (
          <EmptyState
            icon={filter === "all" ? MessageSquareIcon : FilterIcon}
            title={filter === "all" ? "No posts yet" : "No posts match"}
            description={more ? "Show older to look further back." : "Posts from this guru appear here as they arrive."}
            action={more ? undefined : filter === "all" ? { label: "Open Connections", onClick: () => navigate("settings", "connections") } : { label: "Clear filter", onClick: () => onFilterChange("all") }}
          />
        )}
        {days.length > 0 && (
          <div className="flex flex-col gap-6">
            {days.map((day) => (
              <section key={day.label} aria-label={day.label} className="flex flex-col gap-4">
                <h2 className="text-muted-foreground text-xs font-medium">{day.label}</h2>
                <Timeline defaultValue={0}>
                  {day.entries.map((entry, index) => (
                    <PostRow key={entry.post.sequence} entry={entry} guruName={guruName} now={now} step={index + 1} onOpen={onOpen} />
                  ))}
                </Timeline>
              </section>
            ))}
          </div>
        )}
        {posts.status === "ready" && more && (
          <div className="mt-6 flex flex-col items-center gap-2">
            {typeof posts.older === "object" && <RegionError title="Older posts did not load" message={posts.older.error} onRetry={posts.showOlder} />}
            {typeof posts.older !== "object" && (
              <Button type="button" size="sm" variant="outline" onClick={posts.showOlder} disabled={posts.older === "loading"}>
                {posts.older === "loading" && <Spinner data-icon="inline-start" />}
                Show older
              </Button>
            )}
          </div>
        )}
      </FramePanel>
    </Frame>
  )
}
