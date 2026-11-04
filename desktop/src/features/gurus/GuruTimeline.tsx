import { Timeline, TimelineContent, TimelineDate, TimelineHeader, TimelineIndicator, TimelineItem, TimelineSeparator } from "@/components/reui/timeline"
import { PostPicture } from "@/features/activity/PostPicture"
import { quoteOf } from "@/features/activity/PostListItem"
import { readableText } from "@/features/activity/reading"
import { clockTime } from "@/features/activity/time"
import { cn } from "@/lib/utils"
import type { Day, Entry } from "./model"

const dotOf = (entry: Entry): string => {
  const kinds = entry.accounts.map((a) => a.kind)
  if (kinds.includes("traded")) return "border-success bg-success"
  if (entry.isWaiting) return "border-warning bg-warning"
  return kinds.includes("working") ? "border-info bg-info" : ""
}

/** One post on the timeline: the time to the second, the guru's words with how they were read, and what each account did. The dot is green when the post traded. */
function GuruPostEntry({ entry, step, onOpen }: { entry: Entry; step: number; onOpen: (sequence: number) => void }) {
  const { post } = entry
  // A post with no words of its own shows its picture.
  const picture = readableText(post) === "" ? post.source_event?.attachments.find((a) => a.status === "available") : undefined
  return (
    <TimelineItem step={step}>
      <TimelineHeader>
        <TimelineSeparator className="bg-input!" />
        <TimelineIndicator className={cn("bg-background", dotOf(entry))} />
        <TimelineDate className="mb-0 tabular-nums">{clockTime(post.source_at)}</TimelineDate>
      </TimelineHeader>
      <TimelineContent className="text-foreground">
        <button
          type="button"
          onClick={() => onOpen(post.sequence)}
          className="hover:bg-muted focus-visible:ring-ring/50 -mx-2 flex w-[calc(100%+1rem)] flex-col gap-1.5 rounded-lg px-2 py-1.5 text-left outline-none transition-colors focus-visible:ring-3"
        >
          {picture ? <PostPicture attachment={picture} className="max-h-44" /> : <span className="line-clamp-4 text-base break-words">{quoteOf(post)}</span>}
          <span className="text-muted-foreground line-clamp-2 text-xs">{entry.readAs}</span>
          {entry.accounts.map((account) => (
            <span key={account.accountId} className="text-sm">
              <span className="font-medium">{account.accountId}</span>
              <span className={cn("text-muted-foreground", account.kind === "traded" && "text-success-foreground")}> · {account.summary}</span>
            </span>
          ))}
        </button>
      </TimelineContent>
    </TimelineItem>
  )
}

/** Every post of the guru newest first, a timeline for each day. */
export function GuruTimeline({ days, onOpen }: { days: Day[]; onOpen: (sequence: number) => void }) {
  return (
    <div className="flex flex-col gap-6">
      {days.map((day) => (
        <section key={day.label} aria-label={day.label}>
          <h3 className="text-muted-foreground mb-3 text-xs font-medium tracking-wide uppercase">{day.label}</h3>
          <Timeline value={0}>
            {day.entries.map((entry, index) => (
              <GuruPostEntry key={entry.post.sequence} entry={entry} step={index + 1} onOpen={onOpen} />
            ))}
          </Timeline>
        </section>
      ))}
    </div>
  )
}
