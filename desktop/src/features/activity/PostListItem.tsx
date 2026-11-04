import type { SourceActivity } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Item, ItemActions, ItemContent, ItemDescription, ItemTitle } from "@/components/ui/item"
import { href } from "@/features/shell/route"
import { BADGE, cardOutcome } from "./outcome"
import { headline, readableText } from "./reading"
import { clockTime } from "./time"

/** What a list row says of a post: their words, or what came with them in place of words. */
export function quoteOf(post: SourceActivity): string {
  const said = readableText(post)
  if (said) return `“${said}”`
  return (post.source_event?.attachments.length ?? 0) > 0 ? "A picture, no words" : "No message text"
}

/** One post in the list, two lines: their words, then who, when and what it asked for; how it ended is the badge. Opens the post. */
export function PostListItem({ post, guruName, now, selected }: { post: SourceActivity; guruName: string; now: Date; selected: boolean }) {
  const outcome = cardOutcome(post, now)
  // An ignored post has nothing more to say than its badge; a skipped or cancelled call still names what it asked for.
  const asked = post.decision !== "ignore" && !(post.decision === "review" && post.instructions.length === 0)
  return (
    <Item
      size="xs"
      className={selected ? "bg-muted" : undefined}
      render={<a href={href("activity", String(post.sequence))} aria-current={selected ? "true" : undefined} />}
    >
      <ItemContent className="min-w-0 gap-0.5">
        <ItemTitle className="w-full font-normal">
          <span className="truncate">{quoteOf(post)}</span>
        </ItemTitle>
        <ItemDescription className="flex w-full items-baseline gap-3 tabular-nums">
          <span className="max-w-[40%] shrink-0 truncate">{guruName}</span>
          <span className="shrink-0">{clockTime(post.source_at)}</span>
          {asked && <span className="truncate">{headline(post)}</span>}
        </ItemDescription>
      </ItemContent>
      <ItemActions>
        <Badge variant={BADGE[outcome.tone]}>{outcome.title}</Badge>
      </ItemActions>
    </Item>
  )
}
