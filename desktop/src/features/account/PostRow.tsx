import type { SourceActivity } from "../../../shared/contract"
import { Meta } from "@/components/meta"
import { Badge } from "@/components/reui/badge"
import { Item, ItemActions, ItemContent, ItemDescription, ItemTitle } from "@/components/ui/item"
import { dateTime } from "@/lib/format"
import { postOutcome } from "./model"

/** One guru post and what it did here. The text is untrusted Discord content: rendered as text only. */
export function PostRow({ post, accountId, now }: { post: SourceActivity; accountId: string; now: Date }) {
  const outcome = postOutcome(post, accountId, now)
  return (
    <Item size="xs">
      <ItemContent className="gap-0.5">
        <ItemTitle className="w-full font-normal">
          <span className="truncate">{post.text}</span>
        </ItemTitle>
        <ItemDescription className="tabular-nums">
          {/* Chat has nothing more to say than its badge. */}
          <Meta items={[dateTime(post.source_at), ...(post.decision === "ignore" ? [] : outcome.read.split(" · "))]} />
        </ItemDescription>
      </ItemContent>
      <ItemActions>
        <Badge variant={outcome.tone}>{outcome.label}</Badge>
      </ItemActions>
    </Item>
  )
}
