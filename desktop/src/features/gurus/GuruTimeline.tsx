import { CheckIcon, ClockIcon, CircleAlertIcon, MinusIcon, type LucideIcon } from "lucide-react"
import { Timeline, TimelineContent, TimelineHeader, TimelineIndicator, TimelineItem, TimelineSeparator, TimelineTitle } from "@/components/reui/timeline"
import { PostPicture } from "@/features/activity/PostPicture"
import { quoteOf } from "@/features/activity/PostListItem"
import { pictureOf } from "@/features/activity/reading"
import { clockTime } from "@/features/activity/time"
import { cn } from "@/lib/utils"
import type { Day, Entry } from "./model"

/** The node's icon and fill say what became of the post: traded, waiting for the owner, working, or nothing to do. */
function markOf(entry: Entry): { icon: LucideIcon; className: string } {
  const kinds = entry.accounts.map((a) => a.kind)
  if (kinds.includes("traded")) return { icon: CheckIcon, className: "bg-success text-white" }
  if (entry.isWaiting) return { icon: CircleAlertIcon, className: "bg-warning text-white" }
  if (kinds.includes("working")) return { icon: ClockIcon, className: "bg-info text-white" }
  return { icon: MinusIcon, className: "" }
}

/** One post on the timeline (the "Git Activity" timeline, a node per kind of event): the time to the second, the guru's words with how they were read, and what each account did. */
function GuruPostEntry({ entry, step, onOpen }: { entry: Entry; step: number; onOpen: (sequence: number) => void }) {
  const { post } = entry
  const { icon: Icon, className } = markOf(entry)
  // A post with no words of its own shows its picture.
  const picture = pictureOf(post)
  return (
    <TimelineItem step={step} className="group-data-[orientation=vertical]/timeline:ms-10">
      <TimelineHeader>
        <TimelineSeparator className="group-data-[orientation=vertical]/timeline:-left-7 group-data-[orientation=vertical]/timeline:h-[calc(100%-1.5rem-0.25rem)] group-data-[orientation=vertical]/timeline:translate-y-6.5" />
        <TimelineTitle className="mt-0.5 tabular-nums">{clockTime(post.source_at)}</TimelineTitle>
        <TimelineIndicator className={cn("bg-primary/10 flex size-6 items-center justify-center border-none group-data-[orientation=vertical]/timeline:-left-7", className)}>
          <Icon aria-hidden className="size-3.5" />
        </TimelineIndicator>
      </TimelineHeader>
      <TimelineContent className="text-foreground">
        <button
          type="button"
          data-sequence={post.sequence}
          onClick={() => onOpen(post.sequence)}
          className="hover:bg-muted focus-visible:ring-ring/50 -mx-2 flex w-[calc(100%+1rem)] flex-col gap-1.5 rounded-lg px-2 py-1.5 text-left outline-none transition-colors focus-visible:ring-3"
        >
          {picture ? <PostPicture attachment={picture} className="max-h-44" /> : <span className="line-clamp-4 text-base break-words">{quoteOf(post)}</span>}
          {/* A post that was only chat has nothing to add to its icon. */}
          {post.decision !== "ignore" && <span className="text-muted-foreground text-xs">{entry.readAs}</span>}
          {entry.accounts.map((account) => (
            <span key={account.accountId} className="flex items-baseline gap-3 text-sm">
              <span className="font-medium">{account.accountId}</span>
              <span className={cn("text-muted-foreground", account.kind === "traded" && "text-success-foreground dark:text-success")}>{account.summary}</span>
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
          <h3 className="mb-3 text-sm font-semibold tracking-tight">{day.label}</h3>
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
