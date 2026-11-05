// ReUI's Finance Activity Sheet (timeline-9), installed as shipped: the inset right sheet, its header with the title and a
// badge, the close button and the scrolling body. The body is the post in full instead of the block's feed.
import { Cancel01Icon } from "@/components/icons/Cancel01Icon"
import type { SourceActivity } from "../../../shared/contract"
import { Button } from "@/components/ui/button"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Sheet, SheetClose, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { OutcomeBadge } from "@/features/activity/OutcomeBadge"
import { PostDetail } from "@/features/activity/PostDetail"
import { cardOutcome } from "@/features/activity/outcome"
import { postTime } from "@/features/activity/time"

export function GuruPostSheet({ post, guruName, now, onClose }: { post: SourceActivity | undefined; guruName: string; now: Date; onClose: () => void }) {
  const outcome = post && cardOutcome(post, now)
  return (
    <Sheet open={post !== undefined} onOpenChange={(next) => !next && onClose()}>
      <SheetContent
        side="right"
        showCloseButton={false}
        initialFocus={false}
        className="bg-popover flex flex-col overflow-hidden rounded-xl p-0 outline-none data-[side=right]:inset-y-4 data-[side=right]:right-4 data-[side=right]:left-auto data-[side=right]:h-[calc(100svh-2rem)] data-[side=right]:w-[min(30rem,calc(100vw-2rem))] data-[side=right]:max-w-none"
      >
        {/* Header */}
        <SheetHeader className="border-border/70 shrink-0 gap-2 border-b px-5 py-4 text-left">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0 flex-1">
              <div className="flex min-w-0 items-center gap-2">
                <SheetTitle className="truncate">{guruName}</SheetTitle>
                {outcome && <OutcomeBadge title={outcome.title} tone={outcome.tone} />}
              </div>
              <SheetDescription className="text-xs tabular-nums">{post ? postTime(post.source_at) : "The post in full, and what each account did."}</SheetDescription>
            </div>

            <SheetClose
              render={
                <Button type="button" variant="ghost" size="icon-sm" aria-label="Close the post" className="shrink-0">
                  <Cancel01Icon aria-hidden="true" />
                </Button>
              }
            />
          </div>
        </SheetHeader>

        {/* Content */}
        <div className="min-h-0 flex-1">
          <ScrollArea className="h-full min-h-0" aria-label="The post in full">
            <div className="px-5 pt-4 pb-5">{post && <PostDetail post={post} now={now} />}</div>
          </ScrollArea>
        </div>
      </SheetContent>
    </Sheet>
  )
}
