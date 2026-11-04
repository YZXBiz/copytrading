import type { SourceActivity } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Item, ItemActions, ItemContent, ItemDescription, ItemTitle } from "@/components/ui/item"
import { href } from "@/features/shell/route"
import { BADGE, cardOutcome } from "./outcome"
import { headline, readableText } from "./reading"
import { feedTime } from "./time"

/** What a list row says of a post: their words, or what came with them in place of words. */
export function quoteOf(post: SourceActivity): string {
  const said = readableText(post)
  if (said) return `“${said}”`
  return (post.source_event?.attachments.length ?? 0) > 0 ? "A picture, no words" : "No message text"
}

/** One post in the list: who and when, their words, what it asked for, and how it ended. Opens the post. */
export function PostListItem({ post, guruName, now, selected }: { post: SourceActivity; guruName: string; now: Date; selected: boolean }) {
  const outcome = cardOutcome(post, now)
  return (
    <Item
      size="xs"
      className={selected ? "bg-muted" : undefined}
      render={<a href={href("activity", String(post.sequence))} aria-current={selected ? "true" : undefined} />}
    >
      <ItemContent className="gap-0.5">
        <ItemDescription className="flex w-full items-baseline justify-between gap-3 tabular-nums">
          <span className="truncate">{guruName}</span>
          <span className="shrink-0">{feedTime(post.source_at, now)}</span>
        </ItemDescription>
        <ItemTitle className="line-clamp-2 w-full font-normal break-words">{quoteOf(post)}</ItemTitle>
        {/* An ignored post has nothing more to say than its badge; a skipped or cancelled call still names what it asked for. */}
        {post.decision !== "ignore" && !(post.decision === "review" && post.instructions.length === 0) && (
          <ItemDescription className="line-clamp-1">{headline(post)}</ItemDescription>
        )}
      </ItemContent>
      <ItemActions>
        <Badge variant={BADGE[outcome.tone]}>{outcome.title}</Badge>
      </ItemActions>
    </Item>
  )
}
