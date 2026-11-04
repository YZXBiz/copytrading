import type { SourceActivity } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Item, ItemActions, ItemContent, ItemDescription, ItemTitle } from "@/components/ui/item"
import { PostPicture } from "@/features/activity/PostPicture"
import { pictureOf, readableText } from "@/features/activity/reading"
import { dateTime } from "@/lib/format"
import { postOutcome } from "./model"

/** One guru post and what it did here: their words (or their picture when they wrote none), what became of it, and when. The text is untrusted Discord content: rendered as text only. */
export function PostRow({ post, accountId, now }: { post: SourceActivity; accountId: string; now: Date }) {
  const outcome = postOutcome(post, accountId, now)
  const said = readableText(post)
  const picture = pictureOf(post)
  // Chat, and a call still waiting for the owner, have nothing to add to their badge.
  const quiet = post.decision === "ignore" || outcome.tone === "warning-light"
  return (
    <Item size="xs">
      <ItemContent className="gap-0.5">
        {said && (
          <ItemTitle className="w-full font-normal">
            <span className="truncate">{said}</span>
          </ItemTitle>
        )}
        {picture && <PostPicture attachment={picture} className="max-h-16" />}
        {!quiet && outcome.read && <ItemDescription>{outcome.read}</ItemDescription>}
      </ItemContent>
      <ItemActions className="flex-col items-end gap-1">
        <Badge variant={outcome.tone}>{outcome.label}</Badge>
        <span className="text-muted-foreground text-xs tabular-nums">{dateTime(post.source_at)}</span>
      </ItemActions>
    </Item>
  )
}
