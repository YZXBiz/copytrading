import type { SourceActivity } from "../../../shared/contract"
import { Meta } from "@/components/meta"
import { Badge } from "@/components/reui/badge"
import { Separator } from "@/components/ui/separator"
import { AccountResults } from "./AccountResults"
import { PostQuote } from "./PostQuote"
import { ReadAs } from "./ReadAs"
import { BADGE, cardOutcome } from "./outcome"
import { postTime } from "./time"

/**
 * One post in full: who and when with how it ended, their own words, how the reader read them, and what each
 * account did. `accountId` narrows the accounts to one.
 */
export function PostView({ post, guruName, now, accountId = null }: { post: SourceActivity; guruName: string; now: Date; accountId?: string | null }) {
  const outcome = cardOutcome(post, now)
  return (
    <article className="flex flex-col gap-6">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-muted-foreground text-sm tabular-nums">
          <Meta items={[guruName, postTime(post.source_at)]} />
        </p>
        <Badge variant={BADGE[outcome.tone]}>{outcome.title}</Badge>
      </header>
      <PostQuote post={post} />
      <Separator />
      <ReadAs post={post} />
      {post.decision !== "ignore" && (
        <>
          <Separator />
          <AccountResults post={post} now={now} accountId={accountId} />
        </>
      )}
    </article>
  )
}
