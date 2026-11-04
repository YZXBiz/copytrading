import { Fragment } from "react"
import { MessageSquareIcon } from "lucide-react"
import type { SourceActivityPage } from "../../../shared/contract"
import { Frame, FrameDescription, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { ItemGroup, ItemSeparator } from "@/components/ui/item"
import { Skeleton } from "@/components/ui/skeleton"
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
    <Frame spacing="sm">
      <FrameHeader>
        <FrameTitle>Guru posts</FrameTitle>
        <FrameDescription>What each one did here</FrameDescription>
      </FrameHeader>
      <FramePanel className="p-0">
        {posts.status === "loading" && (
          <div role="status" aria-label="Loading posts" className="flex flex-col gap-4 p-3">
            {Array.from({ length: 4 }, (_, i) => (
              <div key={i} className="flex flex-col gap-1.5">
                <Skeleton className="h-4 w-3/4" />
                <Skeleton className="h-3 w-1/3" />
              </div>
            ))}
          </div>
        )}
        {posts.status === "error" && (
          <div className="p-3">
            <RegionError title="Guru posts did not load" message={posts.error} onRetry={posts.retry} />
          </div>
        )}
        {posts.status === "ready" && posts.data.items.length === 0 && (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <MessageSquareIcon />
              </EmptyMedia>
              <EmptyTitle>No posts yet</EmptyTitle>
              <EmptyDescription>Posts from the gurus you copy appear here as they arrive.</EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Button type="button" size="sm" variant="outline" onClick={posts.retry}>
                Refresh
              </Button>
            </EmptyContent>
          </Empty>
        )}
        {posts.status === "ready" && posts.data.items.length > 0 && (
          <ItemGroup>
            {posts.data.items.map((post, index) => (
              <Fragment key={post.sequence}>
                {index > 0 && <ItemSeparator />}
                <PostRow post={post} accountId={accountId} now={now} />
              </Fragment>
            ))}
          </ItemGroup>
        )}
      </FramePanel>
    </Frame>
  )
}
