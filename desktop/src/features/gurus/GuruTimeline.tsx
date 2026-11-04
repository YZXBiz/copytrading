// ReUI's Finance Activity (timeline-3), installed as shipped: an avatar node and its line, a sentence, a muted detail line, an
// action button and the date with a status badge. Its attachment and participants have no counterpart here.
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import { Timeline, TimelineContent, TimelineDate, TimelineHeader, TimelineIndicator, TimelineItem, TimelineSeparator } from "@/components/reui/timeline"
import { OutcomeBadge } from "@/features/activity/OutcomeBadge"
import { PostPicture } from "@/features/activity/PostPicture"
import { cardOutcome } from "@/features/activity/outcome"
import { pictureOf, readableText } from "@/features/activity/reading"
import { clockTime } from "@/features/activity/time"
import type { Day, Entry } from "./model"

function GuruPostEntry({ entry, guruName, now, step, onOpen }: { entry: Entry; guruName: string; now: Date; step: number; onOpen: (sequence: number) => void }) {
  const { post } = entry
  const outcome = cardOutcome(post, now)
  // A post with no words of its own shows its picture.
  const picture = pictureOf(post)
  const said = readableText(post)
  // A post that was only chat has nothing to add to its badge.
  const detail = post.decision !== "ignore" && !(post.decision === "review" && post.instructions.length === 0)
  return (
    <TimelineItem step={step} className="group-data-[orientation=vertical]/timeline:ms-10 group-data-[orientation=vertical]/timeline:not-last:pb-4">
      <TimelineHeader>
        <TimelineSeparator className="bg-border! group-data-[orientation=vertical]/timeline:top-2 group-data-[orientation=vertical]/timeline:-left-8 group-data-[orientation=vertical]/timeline:h-[calc(100%-2.25rem)] group-data-[orientation=vertical]/timeline:translate-y-6" />
        <TimelineIndicator className="size-7 overflow-hidden rounded-full border-none group-data-[orientation=vertical]/timeline:-left-8">
          <Avatar className="size-7">
            <AvatarFallback className="text-[10px] font-medium">{Array.from(guruName)[0]}</AvatarFallback>
          </Avatar>
        </TimelineIndicator>
      </TimelineHeader>

      <TimelineContent className="min-w-0 pb-1">
        <div className="min-w-0">
          <p className="text-sm leading-5">
            <span className="text-foreground font-medium">{guruName}</span> <span className="text-muted-foreground">{picture ? "posted a picture" : said ? "posted" : "posted no words"}</span>{" "}
            {said && <span className="text-foreground line-clamp-2 font-medium break-words">“{said}”</span>}
          </p>
        </div>
        {detail && <p className="text-muted-foreground mt-1 text-xs leading-4">{entry.readAs}</p>}
        {entry.accounts.map((account) => (
          <p key={account.accountId} className="text-muted-foreground mt-1 text-xs leading-4">
            <span className="text-foreground font-medium">{account.accountId}</span> {account.summary}
          </p>
        ))}
        {picture && (
          <div className="mt-2">
            <PostPicture attachment={picture} className="max-h-32" />
          </div>
        )}
        <div className="mt-2 flex max-w-full flex-wrap items-center gap-1.5">
          <Button type="button" size="xs" variant="outline" data-sequence={post.sequence} onClick={() => onOpen(post.sequence)}>
            View post
          </Button>
        </div>
        <div className="mt-2 flex flex-wrap items-center gap-1.5">
          <TimelineDate dateTime={post.source_at} className="mt-0 mb-0">
            {clockTime(post.source_at)}
          </TimelineDate>
          <OutcomeBadge title={outcome.title} tone={outcome.tone} />
        </div>
      </TimelineContent>
    </TimelineItem>
  )
}

/** Every post of the guru newest first, a timeline for each day. */
export function GuruTimeline({ days, guruName, now, onOpen }: { days: Day[]; guruName: string; now: Date; onOpen: (sequence: number) => void }) {
  return (
    <div className="space-y-8">
      {days.map((day) => (
        <section key={day.label} aria-label={day.label} className="space-y-4">
          <h2 className="text-muted-foreground text-xs font-semibold tracking-wide uppercase">{day.label}</h2>
          <Timeline defaultValue={day.entries.length}>
            {day.entries.map((entry, index) => (
              <GuruPostEntry key={entry.post.sequence} entry={entry} guruName={guruName} now={now} step={index + 1} onOpen={onOpen} />
            ))}
          </Timeline>
        </section>
      ))}
    </div>
  )
}
