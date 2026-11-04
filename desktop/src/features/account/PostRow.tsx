import { MessageSquareIcon } from "lucide-react"
import type { SourceActivity } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Item, ItemMedia } from "@/components/ui/item"
import { Separator } from "@/components/ui/separator"
import { PostPicture } from "@/features/activity/PostPicture"
import { pictureOf, readableText } from "@/features/activity/reading"
import { dateTime } from "@/lib/format"
import { cn } from "@/lib/utils"
import { type OutcomeTone, postOutcome } from "./model"

/** The tile's colour says what became of the post, as list-7's category tiles say what a payment was. */
const TILE: Record<OutcomeTone, string> = {
  "success-light": "bg-emerald-600 dark:bg-emerald-500",
  "destructive-light": "bg-red-600 dark:bg-red-500",
  "warning-light": "bg-amber-500 dark:bg-amber-500",
  "info-light": "bg-sky-600 dark:bg-sky-500",
  outline: "bg-slate-500 dark:bg-slate-600",
}

/**
 * One guru post, as ReUI's Spending Feed (list-7) row: a tile, their words (or "A picture" when they wrote none)
 * and when, and on the right what became of it. The post is untrusted Discord content: rendered as text only.
 */
export function PostRow({ post, accountId, now, showSeparator }: { post: SourceActivity; accountId: string; now: Date; showSeparator: boolean }) {
  const outcome = postOutcome(post, accountId, now)
  const said = readableText(post)
  const picture = pictureOf(post)
  // Chat, and a call still waiting for the owner, have nothing to add to their badge.
  const quiet = post.decision === "ignore" || outcome.tone === "warning-light"
  return (
    <li>
      <div className="flex items-center gap-2">
        {/* Their picture stands in the tile when they wrote no words. */}
        {picture && !said ? (
          <PostPicture attachment={picture} className="size-12 max-h-12 shrink-0 object-cover" />
        ) : (
          <Item
            className={cn(
              "p-0",
              "border-background flex size-12 shrink-0 items-center justify-center overflow-hidden border-3 shadow-[0_1px_3px_0_rgba(0,0,0,0.14)] dark:border-3 [&_svg]:size-5.5 [&_svg]:text-white",
              TILE[outcome.tone],
            )}
          >
            <ItemMedia variant="icon" className="size-auto">
              <MessageSquareIcon aria-hidden="true" />
            </ItemMedia>
          </Item>
        )}

        <div className="flex min-w-0 flex-1 flex-col gap-0">
          <p className="text-foreground truncate text-base leading-5 font-medium">{said || "A picture"}</p>
          <p className="text-muted-foreground truncate text-sm leading-4">
            {[dateTime(post.source_at), !quiet && outcome.read].filter(Boolean).join(" · ")}
          </p>
        </div>

        <Badge variant={outcome.tone} className="shrink-0">
          {outcome.label}
        </Badge>
      </div>
      {showSeparator ? <Separator className="my-3.5 w-auto border-t border-dashed bg-transparent" /> : null}
    </li>
  )
}
