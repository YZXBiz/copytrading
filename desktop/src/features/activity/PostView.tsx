import type { SourceActivity } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Frame, FramePanel } from "@/components/reui/frame"
import { AccountResults } from "./AccountResults"
import { PostQuote } from "./PostQuote"
import { ReadAs } from "./ReadAs"
import { BADGE, cardOutcome } from "./outcome"
import { postTime } from "./time"

/**
 * One post in full, as a stack of panels: who and when with how it ended and their own words, how the reader read
 * them, then what each account did. `accountId` narrows the accounts to one.
 */
export function PostView({ post, guruName, now, accountId = null, className }: { post: SourceActivity; guruName: string; now: Date; accountId?: string | null; className?: string }) {
  const outcome = cardOutcome(post, now)
  return (
    <Frame spacing="sm" className={className} role="article" aria-label={`Post by ${guruName}`}>
      <FramePanel className="flex flex-col gap-4">
        <header className="flex items-start justify-between gap-3">
          <div className="flex min-w-0 flex-col">
            <p className="truncate text-sm font-medium">{guruName}</p>
            <p className="text-muted-foreground text-xs tabular-nums">{postTime(post.source_at)}</p>
          </div>
          <Badge variant={BADGE[outcome.tone]}>{outcome.title}</Badge>
        </header>
        <PostQuote post={post} />
      </FramePanel>
      <FramePanel>
        <ReadAs post={post} />
      </FramePanel>
      {post.decision !== "ignore" && <AccountResults post={post} now={now} accountId={accountId} />}
    </Frame>
  )
}
