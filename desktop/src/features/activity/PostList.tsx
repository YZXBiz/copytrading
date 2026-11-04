import { Fragment } from "react"
import { MessageSquareIcon } from "lucide-react"
import type { SourceActivity } from "../../../shared/contract"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Empty, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { ItemGroup, ItemSeparator } from "@/components/ui/item"
import { Skeleton } from "@/components/ui/skeleton"
import { Spinner } from "@/components/ui/spinner"
import { PostListItem } from "./PostListItem"
import { groupByDay } from "./time"
import type { Posts } from "./use-posts"

export function PostListSkeleton() {
  return (
    <div role="status" aria-label="Loading posts" className="flex flex-col gap-4 p-3">
      {Array.from({ length: 6 }, (_, i) => (
        <div key={i} className="flex items-center justify-between gap-4">
          <div className="flex min-w-0 flex-1 flex-col gap-1.5">
            <Skeleton className="h-4 w-3/4" />
            <Skeleton className="h-3 w-1/2" />
          </div>
          <Skeleton className="h-5 w-16" />
        </div>
      ))}
    </div>
  )
}

/** The posts newest first, with Show older at the foot while the engine has older ones. */
export function PostList({
  posts,
  shown,
  selected,
  guruName,
  now,
  emptyTitle,
  emptyHint,
}: {
  posts: Posts
  /** The loaded posts that pass the filters. */
  shown: SourceActivity[]
  selected: number | undefined
  guruName: (id: string | null) => string
  now: Date
  emptyTitle: string
  emptyHint: string
}) {
  if (posts.status === "loading") return <PostListSkeleton />
  if (posts.status === "error") {
    return (
      <div className="p-3">
        <RegionError title="Posts did not load" message={posts.error} onRetry={posts.retry} />
      </div>
    )
  }
  const older = posts.hasOlder && (
    <div className="flex flex-col items-center gap-2 p-3">
      {typeof posts.older === "object" && <RegionError title="Older posts did not load" message={posts.older.error} onRetry={posts.showOlder} />}
      {typeof posts.older !== "object" && (
        <Button type="button" size="sm" variant="outline" onClick={posts.showOlder} disabled={posts.older === "loading"}>
          {posts.older === "loading" && <Spinner data-icon="inline-start" />}
          Show older
        </Button>
      )}
    </div>
  )
  return (
    <>
      {shown.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <MessageSquareIcon />
            </EmptyMedia>
            <EmptyTitle>{emptyTitle}</EmptyTitle>
            <EmptyDescription>{posts.hasOlder ? "Show older to look further back." : emptyHint}</EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        groupByDay(shown, (post) => post.source_at, now).map(({ label, items }) => (
          <section key={label} aria-label={label}>
            <h3 className="text-muted-foreground px-3 pt-3 pb-1 text-xs font-medium">{label}</h3>
            <ItemGroup className="gap-0 px-1 pb-1">
              {items.map((post, index) => (
                <Fragment key={post.sequence}>
                  {index > 0 && <ItemSeparator className="my-0" />}
                  <PostListItem post={post} guruName={guruName(post.guru_id)} now={now} selected={post.sequence === selected} />
                </Fragment>
              ))}
            </ItemGroup>
          </section>
        ))
      )}
      {older}
    </>
  )
}
