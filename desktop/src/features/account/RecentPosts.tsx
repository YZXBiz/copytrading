// ReUI's Spending Feed (list-7), installed as shipped and wired to the guru's posts: the header, a row per post,
// and the footer button, which opens Activity. The block's Weekly and All Time tabs have nothing behind them here.
import { ExternalLinkIcon, MessageSquareIcon } from "lucide-react"
import type { SourceActivityPage } from "../../../shared/contract"
import { Frame, FramePanel } from "@/components/reui/frame"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { EmptyState } from "@/components/empty-state"
import { Skeleton } from "@/components/ui/skeleton"
import { navigate } from "@/features/shell/route"
import { type Loaded } from "@/lib/use-result"
import { PostRow } from "./PostRow"

export function RecentPosts({
  accountId,
  posts,
  now,
}: {
  accountId: string
  posts: Loaded<SourceActivityPage> & { retry: () => void }
  now: Date
}) {
  return (
    <Frame stacked className="@container w-full">
      <FramePanel className="flex items-center justify-between gap-4 p-3.5!">
        {/* Header */}
        <h2 className="text-foreground text-base font-medium">Guru posts</h2>
      </FramePanel>

      <FramePanel className="p-4!">
        {/* Content */}
        {posts.status === "loading" && (
          <div role="status" aria-label="Loading posts" className="flex flex-col gap-3.5">
            {Array.from({ length: 4 }, (_, i) => (
              <div key={i} className="flex items-center gap-2">
                <Skeleton className="size-12 shrink-0 rounded-full" />
                <div className="flex flex-1 flex-col gap-1.5">
                  <Skeleton className="h-4 w-3/4" />
                  <Skeleton className="h-3 w-1/3" />
                </div>
              </div>
            ))}
          </div>
        )}
        {posts.status === "error" && <RegionError title="Guru posts did not load" message={posts.error} onRetry={posts.retry} />}
        {posts.status === "ready" && posts.data.items.length === 0 && (
          <EmptyState icon={MessageSquareIcon} title="No posts yet" description="Posts from the gurus you copy appear here as they arrive." action={{ label: "Refresh", onClick: posts.retry }} />
        )}
        {posts.status === "ready" && posts.data.items.length > 0 && (
          <ul className="flex flex-col">
            {posts.data.items.map((post, index, items) => (
              <PostRow key={post.sequence} post={post} accountId={accountId} now={now} showSeparator={index < items.length - 1} />
            ))}
          </ul>
        )}
      </FramePanel>

      <FramePanel className="p-3.5!">
        {/* Footer */}
        <Button variant="outline" size="lg" className="text-foreground w-full" onClick={() => navigate("activity")}>
          <ExternalLinkIcon aria-hidden="true" className="opacity-50" />
          View in Activity
        </Button>
      </FramePanel>
    </Frame>
  )
}
