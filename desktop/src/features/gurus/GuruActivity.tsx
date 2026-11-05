import { useMemo } from "react"
import { FilterIcon } from "@/components/icons/FilterIcon"
import { Message01Icon } from "@/components/icons/Message01Icon"
import { Button } from "@/components/arc/button/button"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { PostFeed, type PostFeedEntry } from "@/features/activity/PostFeed"
import { PostsSkeleton } from "@/features/activity/PostsSkeleton"
import { RegionAlert } from "@/features/activity/RegionAlert"
import type { Posts } from "@/features/activity/use-posts"
import { navigate } from "@/features/shell/route"
import { type Entry, POST_FILTERS, type PostFilter, includesEntry } from "./model"
import styles from "./gurus.module.css"

const FILTERS = POST_FILTERS.map(({ id, label }) => ({ value: id, label }))

/** One guru's posts, newest first by day, under the All, Traded, Waiting and Not traded filter. */
export function GuruActivity({
  guruName,
  now,
  entries,
  more,
  posts,
  filter,
  onFilterChange,
  onOpen,
}: {
  guruName: string
  now: Date
  /** Every loaded post, before the filter. */
  entries: Entry[]
  more: boolean
  posts: Posts
  filter: PostFilter
  onFilterChange: (filter: PostFilter) => void
  onOpen: (sequence: number) => void
}) {
  const feed = useMemo<PostFeedEntry[]>(
    () => entries.map((entry) => ({ post: entry.post, guru: guruName, readAs: entry.readAs, accounts: entry.accounts, kinds: POST_FILTERS.filter(({ id }) => id !== "all" && includesEntry(id, entry)).map(({ id }) => id) })),
    [entries, guruName],
  )
  if (posts.status === "loading") return <PostsSkeleton />
  if (posts.status === "error") return <RegionAlert title="Posts did not load" message={posts.error} onRetry={posts.retry} />
  const failed = typeof posts.older === "object" ? posts.older.error : undefined
  return (
    <PostFeed
      entries={feed}
      now={now}
      filters={FILTERS}
      filter={filter}
      onFilterChange={(value) => onFilterChange(value as PostFilter)}
      onOpen={onOpen}
      resetKey={guruName}
      title="Posts"
      older={more ? { loading: posts.older === "loading", error: failed, show: posts.showOlder } : null}
      empty={
        entries.length === 0 || filter === "all" ? (
          <EmptyState
            icon={<Message01Icon width={24} height={24} aria-hidden="true" />}
            title="No posts yet"
            description={more ? "Show older to look further back." : "Posts from this guru appear here as they arrive."}
            action={
              more ? undefined : (
                <Button variant="secondary" size="sm" onClick={() => navigate("settings", "connections")}>
                  Open Connections
                </Button>
              )
            }
          />
        ) : (
          <EmptyState
            icon={<FilterIcon width={24} height={24} aria-hidden="true" />}
            title="No posts match"
            description={more ? "Show older to look further back." : "No post of this guru fits the filter."}
            action={
              more ? undefined : (
                <Button variant="secondary" size="sm" onClick={() => onFilterChange("all")}>
                  Clear filter
                </Button>
              )
            }
          />
        )
      }
    />
  )
}
