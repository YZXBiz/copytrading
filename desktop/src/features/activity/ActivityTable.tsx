import { useMemo, useState } from "react"
import { Button } from "@/components/arc/button/button"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { SearchField } from "@/components/arc/search-field/search-field"
import SegmentedControl from "@/components/arc/segmented-control/segmented-control"
import { Select } from "@/components/arc/select/select"
import { SortableDataTable, type SortState } from "@/components/arc/sortable-data-table/sortable-data-table"
import { navigate } from "@/features/shell/route"
import { type ActivityRow, matches } from "./activity-rows"
import { activityColumns, tableRow } from "./activity-columns"
import { PostFeed, type PostFeedEntry } from "./PostFeed"
import { BUCKETS, BUCKET_LABEL, type Bucket } from "./post-bucket"
import styles from "./activity.module.css"

export type PostFilter = "all" | Bucket
const FILTERS: { value: PostFilter; label: string }[] = [{ value: "all", label: "All posts" }, ...BUCKETS.map((b) => ({ value: b, label: BUCKET_LABEL[b] }))]
const VIEWS = [
  { value: "feed", label: "Feed" },
  { value: "table", label: "Table" },
]
/** Table rows drawn at first and per press of "Show more". */
const STEP = 30

/** Guru posts newest first, as a feed by day or as a table to sort and search; a post opens beside them. */
export function ActivityPosts({
  rows,
  now,
  accountIds,
  accountId,
  onAccountChange,
  filter,
  onFilterChange,
  older,
}: {
  rows: ActivityRow[]
  now: Date
  accountIds: string[]
  accountId: string | null
  onAccountChange: (id: string | null) => void
  filter: PostFilter
  onFilterChange: (filter: PostFilter) => void
  /** Reads posts older than the ones loaded, when there are some. */
  older: { loading: boolean; show: () => void } | null
}) {
  const [view, setView] = useState("feed")
  const [query, setQuery] = useState("")
  const [count, setCount] = useState(STEP)
  const [sort, setSort] = useState<SortState>({ key: "time", direction: "desc" })
  const open = (sequence: number) => navigate("activity", String(sequence))

  const shown = useMemo(() => rows.filter((row) => (accountId === null || row.accounts.length > 0) && matches(row, query)), [rows, accountId, query])
  const entries = useMemo<PostFeedEntry[]>(() => shown.map((row) => ({ post: row.post, guru: row.guru, readAs: row.meaning, accounts: row.accounts, kinds: row.bucket ? [row.bucket] : [] })), [shown])
  const kept = useMemo(() => shown.filter((row) => filter === "all" || row.bucket === filter), [shown, filter])
  const columns = useMemo(() => activityColumns({ onOpen: (row) => open(row.post.sequence) }), [])
  // A header sorts every post that passes the filters, then the first rows of that order are drawn.
  const tableRows = useMemo(() => {
    const collator = new Intl.Collator("en", { numeric: true, sensitivity: "base" })
    const sign = sort.direction === "asc" ? 1 : -1
    return kept
      .map(tableRow)
      .sort((a, b) => sign * collator.compare(String(a[sort.key]), String(b[sort.key])))
      .slice(0, count)
  }, [kept, count, sort])
  const choices = [{ value: "all", label: "All accounts" }, ...accountIds.map((id) => ({ value: id, label: id }))]

  const clear = (
    <EmptyState
      title="No posts match"
      description="Try another word, filter or account."
      action={
        <Button
          variant="secondary"
          size="sm"
          onClick={() => {
            setQuery("")
            onFilterChange("all")
            onAccountChange(null)
          }}
        >
          Clear filters
        </Button>
      }
    />
  )

  return (
    <section className={styles.posts} aria-label="Guru posts">
      <div className={styles.toolbar}>
        <div className={styles.search}>
          <SearchField label="Search posts" placeholder="Search posts" value={query} onValueChange={setQuery} />
        </div>
        {accountIds.length > 1 && (
          <Select
            className={styles.account}
            label="Account"
            value={accountId ?? "all"}
            onValueChange={(next) => onAccountChange(next === "all" ? null : next)}
            options={choices}
          />
        )}
        <span className={styles.spacer} />
        <SegmentedControl label="View" options={VIEWS} value={view} onValueChange={setView} />
      </div>
      {view === "feed" ? (
        <PostFeed
          entries={entries}
          now={now}
          filters={FILTERS}
          filter={filter}
          onFilterChange={(value) => onFilterChange(value as PostFilter)}
          onOpen={open}
          resetKey="activity"
          older={older}
          empty={clear}
          title="Guru posts"
        />
      ) : (
        <div className={styles.tablePanel}>
          <header>
            <h2>Guru posts</h2>
            <SegmentedControl label="Filter posts" options={FILTERS} value={filter} onValueChange={(value) => onFilterChange(value as PostFilter)} />
          </header>
          <div className={styles.tableScroll}>
            <SortableDataTable
              rows={tableRows}
              columns={columns}
              rowKey="id"
              caption="Guru posts"
              emptyMessage="No posts match the current view."
              defaultSort={sort}
              onSortChange={setSort}
              itemName={{ one: "post", other: "posts" }}
            />
          </div>
          {(kept.length > count || older) && (
            <div className={styles.more}>
              {kept.length > count ? (
                <Button variant="secondary" size="sm" onClick={() => setCount(count + STEP)}>
                  Show more
                </Button>
              ) : (
                older && (
                  <Button variant="secondary" size="sm" loading={older.loading} onClick={older.show}>
                    Show older
                  </Button>
                )
              )}
            </div>
          )}
        </div>
      )}
    </section>
  )
}
