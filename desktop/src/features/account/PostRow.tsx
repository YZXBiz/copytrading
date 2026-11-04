import type { SourceActivity } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Item, ItemActions, ItemContent, ItemTitle } from "@/components/ui/item"
import { PostPicture } from "@/features/activity/PostPicture"
import { pictureOf, readableText } from "@/features/activity/reading"
import { dateTime } from "@/lib/format"
import { postOutcome } from "./model"

/**
 * One guru post, one line, as the waiting list: their words (or their picture when they wrote none) truncated, then what
 * became of it and when. The post is untrusted Discord content: rendered as text only. What the post meant for this
 * account reads on hover.
 */
export function PostRow({ post, accountId, now }: { post: SourceActivity; accountId: string; now: Date }) {
  const outcome = postOutcome(post, accountId, now)
  const said = readableText(post)
  const picture = pictureOf(post)
  // Chat, and a call still waiting for the owner, have nothing to add to their badge.
  const quiet = post.decision === "ignore" || outcome.tone === "warning-light"
  return (
    <Item size="xs" title={!quiet && outcome.read ? outcome.read : undefined}>
      <ItemContent className="min-w-0 basis-64">
        {said && (
          <ItemTitle className="w-full font-normal">
            <span className="truncate">{said}</span>
          </ItemTitle>
        )}
        {picture && <PostPicture attachment={picture} className="max-h-8" />}
      </ItemContent>
      <ItemActions className="shrink-0 gap-3">
        <Badge variant={outcome.tone}>{outcome.label}</Badge>
        <span className="text-muted-foreground w-28 text-end text-xs tabular-nums">{dateTime(post.source_at)}</span>
      </ItemActions>
    </Item>
  )
}
