"use client"

import { useMemo, useState } from "react"
import type { SourceActivityPage } from "../../../shared/contract"
import { Badge } from "@/components/arc/badge/badge"
import { Button } from "@/components/arc/button/button"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { Pagination } from "@/components/arc/pagination/pagination"
import { SearchField } from "@/components/arc/search-field/search-field"
import SegmentedControl from "@/components/arc/segmented-control/segmented-control"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import SortableDataTable from "@/components/arc/sortable-data-table/sortable-data-table"
import { endOfTradingDay, untilText } from "@/features/activity/deadline"
import { namedBuyNote } from "@/features/activity/outcome"
import { PostPicture } from "@/features/activity/PostPicture"
import { pictureOf, readableText } from "@/features/activity/reading"
import { navigate } from "@/features/shell/route"
import { dateTime } from "@/lib/format"
import { type Loaded } from "@/lib/use-result"
import styles from "./account.module.css"
import { type OutcomeTone } from "./model"
import type { Recent } from "./skipped-calls"
import { type PostFilter, type PostTableRow, POST_FILTERS, postRows } from "./post-rows"
import { RegionNote } from "./RegionNote"
import { type WaitingCall, gainLine } from "./waiting"

const PAGE_SIZE = 8

/** The badge tone of what became of a post, in Activity's own tones. */
const TONE: Record<OutcomeTone, "neutral" | "success" | "warning" | "danger" | "info"> = {
  "success-light": "success",
  "warning-light": "warning",
  "destructive-light": "danger",
  "info-light": "info",
  outline: "neutral",
}

/** The button's word: enter the trade yourself, approve what the account held, or copy what the post called. */
const copyLabel = (call: WaitingCall) => (call.calls.length === 0 ? "Enter trade" : call.awaitsApproval ? "Approve" : "Copy")

type Row = { id: string; post: string; meaning: string; status: string; time: string; row: PostTableRow }

export function PostsTable({
  accountId,
  posts,
  calls,
  canCopy,
  now,
  recent,
  skipped,
  filter,
  onFilterChange,
  onCopy,
  onSkip,
  onSkipAll,
  onUndo,
}: {
  accountId: string
  posts: Loaded<SourceActivityPage> & { retry: () => void }
  calls: WaitingCall[]
  canCopy: boolean
  now: Date
  recent: Recent | null
  skipped: (sourceId: string) => boolean
  filter: PostFilter
  onFilterChange: (filter: PostFilter) => void
  onCopy: (call: WaitingCall) => void
  onSkip: (call: WaitingCall) => void
  onSkipAll: () => void
  onUndo: () => void
}) {
  const [query, setQuery] = useState("")
  const [page, setPage] = useState(1)

  const rows = useMemo(() => (posts.status === "ready" ? postRows(posts.data.items, calls, accountId, now, skipped) : []), [posts, calls, accountId, now, skipped])
  const shown = useMemo(() => {
    const needle = query.trim().toLowerCase()
    return rows.filter((row) => (filter === "all" || row.filter === filter) && (needle === "" || [readableText(row.post), row.meaning, row.label].join(" ").toLowerCase().includes(needle)))
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
        const first = row.call?.calls[0]
        const gain = first ? gainLine(first) : null
        // A sell held for its buy price has no buy to gain on: it says what came of that buy.
        const held = row.call ? namedBuyNote(row.call.source) : null
        return (
          <span className={styles.meaning}>
            <span className={styles.meaningText}>{row.meaning}</span>
            {held ? <span className={styles.muted}>{held}</span> : gain && <Badge tone={gain.change < 0 ? "danger" : "success"}>{gain.line}</Badge>}
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
    {
      key: "actions",
      label: "Actions",
      sortable: false,
      width: 190,
      render: (_: unknown, { row }: Row) =>
        row.call ? (
          <span className={styles.rowActions}>
            <Button type="button" size="sm" variant="ghost" onClick={() => onSkip(row.call!)}>
              Skip
            </Button>
            <Button type="button" size="sm" variant="secondary" disabled={!canCopy} onClick={() => onCopy(row.call!)} title={canCopy ? undefined : "Copying is off, so nothing can be placed yet."}>
              {copyLabel(row.call)}
            </Button>
          </span>
        ) : null,
    },
  ]

  return (
    <section className={styles.panel} aria-labelledby="posts-title">
      <header className={styles.panelHead}>
        <div>
          <h2 id="posts-title" className={styles.panelTitle}>
            Guru posts
          </h2>
          <p className={styles.panelMeta}>{calls.length === 0 ? "Nothing is waiting for you" : calls.length === 1 ? "1 waiting for you" : `${calls.length} waiting for you`}</p>
        </div>
        <div className={styles.tools}>
          {calls.length > 1 && (
            <Button type="button" size="sm" variant="ghost" onClick={onSkipAll}>
              Skip all
            </Button>
          )}
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
      {posts.status === "ready" && rows.length > 0 && shown.length === 0 && (
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
      {recent && (
        <div className={styles.undo} role="status">
          <span className={styles.undoText}>{recent.text ? `Skipped “${recent.text}”` : recent.sourceIds.length > 1 ? `Skipped ${recent.sourceIds.length} calls` : "Skipped"}</span>
          <Button type="button" size="sm" variant="ghost" onClick={onUndo}>
            Undo
          </Button>
        </div>
      )}
    </section>
  )
}
