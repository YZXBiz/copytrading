import type { SourceActivity } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Item, ItemActions, ItemContent, ItemDescription, ItemTitle } from "@/components/ui/item"
import { dateTime } from "@/lib/format"
import { postOutcome } from "./model"

/** One guru post and what it did here. The text is untrusted Discord content: rendered as text only. */
export function PostRow({ post, accountId, now }: { post: SourceActivity; accountId: string; now: Date }) {
  const outcome = postOutcome(post, accountId, now)
  return (
    <Item size="xs">
      <ItemContent>
        <ItemTitle className="w-full">
          <span className="truncate">{post.text}</span>
        </ItemTitle>
        <ItemDescription>
          {dateTime(post.source_at)} · {outcome.read}
        </ItemDescription>
      </ItemContent>
      <ItemActions>
        <Badge variant={outcome.tone}>{outcome.label}</Badge>
      </ItemActions>
    </Item>
  )
}
