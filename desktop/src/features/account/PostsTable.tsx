"use client"

import { useMemo, useRef, useState } from "react"
import type { SourceActivityPage } from "../../../shared/contract"
import { Badge } from "@/components/arc/badge/badge"
import { Button } from "@/components/arc/button/button"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { Pagination } from "@/components/arc/pagination/pagination"
import { SearchField } from "@/components/arc/search-field/search-field"
import SegmentedControl from "@/components/arc/segmented-control/segmented-control"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import SortableDataTable from "@/components/arc/sortable-data-table/sortable-data-table"
import type { UndoToastHandle } from "@/components/arc/undo-toast/undo-toast"
import { endOfTradingDay, untilText } from "@/features/activity/deadline"
import { PostPicture } from "@/features/activity/PostPicture"
import { pictureOf, readableText } from "@/features/activity/reading"
import { navigate } from "@/features/shell/route"
import { dateTime } from "@/lib/format"
import { type Loaded } from "@/lib/use-result"
import styles from "./account.module.css"
import { type OutcomeTone } from "./model"
import { type PostFilter, type PostTableRow, POST_FILTERS, postRows, sourceKey } from "./post-rows"
import { RegionNote } from "./RegionNote"
import { type WaitingCall, callGain } from "./waiting"
import { WaitingQueue } from "./WaitingQueue"

const PAGE_SIZE = 8

/** The badge tone of what became of a post, in Activity's own tones. */
const TONE: Record<OutcomeTone, "neutral" | "success" | "warning" | "danger" | "info"> = {
  "success-light": "success",
  "warning-light": "warning",
  "destructive-light": "danger",
  "info-light": "info",
  outline: "neutral",
}

type Row = { id: string; post: string; meaning: string; status: string; time: string; row: PostTableRow }

export function PostsTable({
  accountId,
  posts,
  calls,
  canCopy,
  now,
  skipped,
  filter,
  onFilterChange,
  onCopy,
}: {
  accountId: string
  posts: Loaded<SourceActivityPage> & { retry: () => void }
  calls: WaitingCall[]
  canCopy: boolean
  now: Date
  skipped: (sourceId: string) => boolean
  filter: PostFilter
  onFilterChange: (filter: PostFilter) => void
  onCopy: (call: WaitingCall) => void
}) {
  const [query, setQuery] = useState("")
  const [page, setPage] = useState(1)
  const queue = useRef<UndoToastHandle>(null)

  const rows = useMemo(() => (posts.status === "ready" ? postRows(posts.data.items, calls, accountId, now, skipped) : []), [posts, calls, accountId, now, skipped])
  // The waiting calls are answered in the queue above, so All and the other filters list the rest; Waiting still lists them.
  const shown = useMemo(() => {
    const needle = query.trim().toLowerCase()
    return rows.filter((row) => (filter === "all" ? !row.call : row.filter === filter) && (needle === "" || [readableText(row.post), row.meaning, row.label].join(" ").toLowerCase().includes(needle)))
  }, [rows, filter, query])
  const pageCount = Math.max(1, Math.ceil(shown.length / PAGE_SIZE))
  const current = Math.min(page, pageCount)
  const visible: Row[] = shown.slice((current - 1) * PAGE_SIZE, current * PAGE_SIZE).map((row) => ({
    id: String(row.post.sequence),
    post: readableText(row.post),
    meaning: row.meaning,
    status: row.label,
    time: row.post.source_at,
    row,
  }))

  /** Pressing a post does what its first button does: review a waiting call, or open the post in Activity. */
  const open = (row: PostTableRow) => (row.call && canCopy ? onCopy(row.call) : navigate("activity", String(row.post.sequence)))

  const columns = [
    {
      key: "post",
      label: "Post",
      sortable: false,
      render: (_: unknown, { row }: Row) => {
        const said = readableText(row.post)
        const picture = pictureOf(row.post)
        return (
          <button type="button" className={styles.postCell} onClick={() => open(row)}>
            {picture && !said && <PostPicture attachment={picture} className={styles.postPicture} />}
            {/* The post is untrusted Discord text: rendered as text, never as HTML. */}
            <span className={styles.postText}>{said ? `“${said}”` : "A picture"}</span>
          </button>
        )
      },
    },
    {
      key: "meaning",
      label: "What it means",
      sortable: false,
      width: 230,
      render: (_: unknown, { row }: Row) => {
        if (!row.meaning) return <span className={styles.muted}>None</span>
        const gain = row.call ? callGain(row.call) : null
        return (
          <span className={styles.meaning}>
            <span className={styles.meaningText}>{row.meaning}</span>
            {gain && <Badge tone={gain.change < 0 ? "danger" : "success"}>{gain.line}</Badge>}
          </span>
        )
      },
    },
    {
      key: "status",
      label: "Status",
      sortable: false,
      width: 130,
      render: (_: unknown, { row }: Row) => (
        <Badge tone={TONE[row.tone]} dot>
          {row.label}
        </Badge>
      ),
    },
    {
      key: "time",
      label: "Time",
      sortable: false,
      width: 150,
      render: (_: unknown, { row }: Row) => (
        <span className={styles.time}>
          <span>{dateTime(row.post.source_at)}</span>
          {row.call && <span className={styles.muted}>{untilText(endOfTradingDay(row.call.source.source_at), now)}</span>}
        </span>
      ),
    },
  ]

  return (
    <section className={styles.panel} aria-labelledby="posts-title">
      <header className={styles.panelHead}>
        <div>
          <h2 id="posts-title" className={styles.panelTitle}>
            Guru posts
          </h2>
          <div className={styles.metaRow}>
            <p className={styles.panelMeta}>{calls.length === 0 ? "Nothing is waiting for you" : calls.length === 1 ? "1 waiting for you" : `${calls.length} waiting for you`}</p>
            {calls.length > 1 && (
              <Button type="button" size="sm" variant="ghost" onClick={() => calls.forEach((call) => queue.current?.remove(sourceKey(call.source), "skip"))}>
                Skip all
              </Button>
            )}
          </div>
        </div>
        <div className={styles.tools}>
          <SearchField
            label="Search posts"
            value={query}
            onValueChange={(value) => {
              setQuery(value)
              setPage(1)
            }}
            placeholder="Search posts"
          />
          <SegmentedControl
            label="Filter posts"
            value={filter}
            onValueChange={(value) => {
              const next = POST_FILTERS.find((option) => option.value === value)?.value
              if (next) {
                onFilterChange(next)
                setPage(1)
              }
            }}
            options={POST_FILTERS}
          />
        </div>
      </header>

      <WaitingQueue calls={calls} accountId={accountId} canCopy={canCopy} now={now} onCopy={onCopy} handle={queue} />

      {posts.status === "loading" && <Skeleton label="Loading posts" lines={4} />}
      {posts.status === "error" && <RegionNote title="Guru posts did not load" message={posts.error} onRetry={posts.retry} />}
      {posts.status === "ready" && rows.length === 0 && (
        <EmptyState
          title="No posts yet"
          description="Posts from the gurus you copy appear here as they arrive."
          action={
            <Button type="button" variant="secondary" size="sm" onClick={posts.retry}>
              Refresh
            </Button>
          }
        />
      )}
      {/* All with nothing else to list means every post is a waiting call, and the queue above is showing them. */}
      {posts.status === "ready" && rows.length > 0 && shown.length === 0 && !(filter === "all" && query.trim() === "") && (
        <EmptyState
          title={filter === "waiting" && query.trim() === "" ? "Nothing is waiting for you" : "No posts match"}
          description={filter === "waiting" && query.trim() === "" ? "Calls that need an answer appear here." : "Try another word or filter."}
          action={
            filter === "waiting" && query.trim() === "" ? (
              <Button type="button" variant="secondary" size="sm" onClick={() => navigate("activity")}>
                See Activity
              </Button>
            ) : undefined
          }
        />
      )}
      {posts.status === "ready" && shown.length > 0 && (
        <>
          <SortableDataTable<Row> rows={visible} columns={columns} rowKey="id" caption="Guru posts" />
          {pageCount > 1 && (
            <div className={styles.pager}>
              <Pagination page={current} pageCount={pageCount} onPageChange={setPage} label="Posts pages" />
            </div>
          )}
        </>
      )}
    </section>
  )
}
