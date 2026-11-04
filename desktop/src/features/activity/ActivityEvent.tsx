import { useState } from "react"
import { ChevronRightIcon } from "lucide-react"
import type { SourceActivity } from "../../../shared/contract"
import { SymbolLogo } from "@/components/symbol-logo"
import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame"
import { Timeline, TimelineContent, TimelineHeader, TimelineIndicator, TimelineItem, TimelineSeparator, TimelineTitle } from "@/components/reui/timeline"
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { cn } from "@/lib/utils"
import { OutcomeBadge, toneIcon } from "./OutcomeBadge"
import { PostDetail } from "./PostDetail"
import { cardOutcome } from "./outcome"
import { headline, quoteOf } from "./reading"
import { clockTime } from "./time"

/**
 * One post on the day's timeline, as ReUI's audit log lays out an event (solution-users-6): what it asked for and how it
 * ended with the time, then a collapsible frame headed by who said it and their words, opening to the post in full.
 */
function ActivityEvent({
  post,
  guruName,
  now,
  accountId,
  step,
  isLast,
  defaultOpen,
}: {
  post: SourceActivity
  guruName: string
  now: Date
  accountId: string | null
  step: number
  isLast: boolean
  defaultOpen: boolean
}) {
  const [open, setOpen] = useState(defaultOpen)
  const outcome = cardOutcome(post, now)
  const Icon = toneIcon(outcome.tone)
  const symbol = post.instructions[0]?.symbol
  return (
    <TimelineItem step={step} className={cn("ms-10", isLast ? "pb-0" : "pb-6")}>
      <TimelineHeader className="flex min-w-0 items-center justify-between gap-2.5">
        <TimelineSeparator className="bg-border! group-data-[orientation=vertical]/timeline:-left-7 group-data-[orientation=vertical]/timeline:h-[calc(100%-1.5rem-0.5rem)] group-data-[orientation=vertical]/timeline:translate-y-7" />
        <div className="flex flex-wrap items-center gap-2">
          <TimelineTitle className="text-sm font-semibold">{headline(post)}</TimelineTitle>
          <OutcomeBadge title={outcome.title} tone={outcome.tone} />
          <span className="text-muted-foreground text-xs tabular-nums">{clockTime(post.source_at)}</span>
        </div>
        <TimelineIndicator className="border-border bg-background text-muted-foreground flex size-6 items-center justify-center overflow-hidden rounded-full border shadow-xs group-data-[orientation=vertical]/timeline:-left-7 [&_svg]:size-3.5">
          {/* A post that names a stock shows its logo here, in place of the tone icon (the badge already says how it ended). */}
          {symbol ? <SymbolLogo symbol={symbol} size="sm" /> : <Icon aria-hidden="true" />}
        </TimelineIndicator>
      </TimelineHeader>

      <TimelineContent className="mt-2">
        <Frame stacked dense spacing="sm">
          <Collapsible open={open} onOpenChange={setOpen} className="group/collapsible">
            <CollapsibleTrigger type="button" data-sequence={post.sequence} className="flex w-full min-w-0" aria-label={`Toggle the post by ${guruName}`}>
              <FrameHeader className="flex min-w-0 grow flex-row items-center justify-between gap-2">
                <div className="flex min-w-0 items-center gap-2">
                  <Avatar className="size-5">
                    <AvatarFallback className="text-[10px]">{Array.from(guruName)[0]}</AvatarFallback>
                  </Avatar>
                  <span className="text-muted-foreground min-w-0 truncate text-sm font-medium">
                    {guruName}, {quoteOf(post)}
                  </span>
                </div>
                <ChevronRightIcon
                  className="text-muted-foreground size-4 shrink-0 transition-transform duration-200 group-data-open/collapsible:rotate-90"
                  aria-hidden="true"
                />
              </FrameHeader>
            </CollapsibleTrigger>

            <CollapsibleContent>
              <FramePanel className="space-y-3">
                <PostDetail post={post} now={now} accountId={accountId} />
              </FramePanel>
            </CollapsibleContent>
          </Collapsible>
        </Frame>
      </TimelineContent>
    </TimelineItem>
  )
}

/** One day's posts, newest first. The post the route names, or the newest, starts open. */
export function ActivityDay({
  posts,
  openSequence,
  guruName,
  now,
  accountId,
}: {
  posts: SourceActivity[]
  openSequence: number | undefined
  guruName: (id: string | null) => string
  now: Date
  accountId: string | null
}) {
  return (
    <Timeline>
      {posts.map((post, index) => (
        <ActivityEvent
          // A new choice of post remounts its row so that it opens.
          key={`${post.sequence}:${post.sequence === openSequence}`}
          post={post}
          guruName={guruName(post.guru_id)}
          now={now}
          accountId={accountId}
          step={index + 1}
          isLast={index === posts.length - 1}
          defaultOpen={post.sequence === openSequence}
        />
      ))}
    </Timeline>
  )
}
