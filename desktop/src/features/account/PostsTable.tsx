// dashboard-8's Recent Moves ledger (a Frame with a search, a filter select and a DataGrid with pagination), wired
// to the guru's posts: the calls waiting for the owner first, with their Skip and Copy, then every other post.
"use client"

import { useMemo, useState } from "react"
import { CheckIcon, EllipsisIcon, MessageSquareIcon } from "lucide-react"
import { type ColumnDef, type PaginationState, useTable } from "@tanstack/react-table"
import type { SourceActivityPage } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { DataGrid, type DataGridFeatures, dataGridFeatures } from "@/components/reui/data-grid/data-grid"
import { DataGridColumnHeader } from "@/components/reui/data-grid/data-grid-column-header"
import { DataGridPagination } from "@/components/reui/data-grid/data-grid-pagination"
import { DataGridScrollArea } from "@/components/reui/data-grid/data-grid-scroll-area"
import { DataGridTable } from "@/components/reui/data-grid/data-grid-table"
import { Frame, FrameDescription, FrameFooter, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { EmptyState } from "@/components/empty-state"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Separator } from "@/components/ui/separator"
import { Skeleton } from "@/components/ui/skeleton"
import { endOfTradingDay, untilText } from "@/features/activity/deadline"
import { namedBuyNote } from "@/features/activity/outcome"
import { PostPicture } from "@/features/activity/PostPicture"
import { pictureOf, readableText } from "@/features/activity/reading"
import { navigate } from "@/features/shell/route"
import { dateTime } from "@/lib/format"
import { type Loaded } from "@/lib/use-result"
import { type OutcomeTone } from "./model"
import type { Recent } from "./skipped-calls"
import { type PostFilter, type PostTableRow, POST_FILTERS, postRows } from "./post-rows"
import { type WaitingCall, gainLine } from "./waiting"

/** The dot in a status badge, by the badge's tone. */
const DOT: Record<OutcomeTone, string> = {
  "success-light": "bg-success",
  "warning-light": "bg-warning",
  "destructive-light": "bg-destructive",
  "info-light": "bg-info",
  outline: "bg-muted-foreground",
}

/** The button's word: enter the trade yourself, approve what the account held, or copy what the post called. */
const copyLabel = (call: WaitingCall) => (call.calls.length === 0 ? "Enter Trade…" : call.awaitsApproval ? "Approve…" : "Copy…")

/** The guru's words as one line; the post is untrusted Discord text, rendered as text, and a picture stands in when they wrote none. */
function PostCell({ row }: { row: PostTableRow }) {
  const said = readableText(row.post)
  const picture = pictureOf(row.post)
  return (
    <div className="flex min-w-0 items-center gap-2">
      {picture && !said && <PostPicture attachment={picture} className="size-6 max-h-6 shrink-0 object-cover" />}
      <span className="truncate text-sm font-medium">{said ? `“${said}”` : "A picture"}</span>
    </div>
  )
}

function MeaningCell({ row }: { row: PostTableRow }) {
  if (!row.meaning) return <span className="text-muted-foreground text-sm">—</span>
  const first = row.call?.calls[0]
  const gain = first ? gainLine(first) : null
  // A sell held for its buy price has no buy to gain on: it says what came of that buy.
  const held = row.call ? namedBuyNote(row.call.source) : null
  return (
    <div className="flex min-w-0 items-center gap-2">
      <span className="truncate text-sm">{row.meaning}</span>
      {held ? <span className="text-muted-foreground shrink-0 text-xs">{held}</span> : gain && <Badge variant={gain.change < 0 ? "destructive-light" : "success-light"}>{gain.line}</Badge>}
    </div>
  )
}

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
  const [pagination, setPagination] = useState<PaginationState>({ pageIndex: 0, pageSize: 8 })
  const resetPage = () => setPagination((current) => (current.pageIndex === 0 ? current : { ...current, pageIndex: 0 }))

  const rows = useMemo(() => (posts.status === "ready" ? postRows(posts.data.items, calls, accountId, now, skipped) : []), [posts, calls, accountId, now, skipped])
  const shown = useMemo(() => {
    const needle = query.trim().toLowerCase()
    return rows.filter((row) => (filter === "all" || row.filter === filter) && (needle === "" || [readableText(row.post), row.meaning, row.label].join(" ").toLowerCase().includes(needle)))
  }, [rows, filter, query])

  const columns = useMemo<ColumnDef<DataGridFeatures, PostTableRow>[]>(
    () => [
      {
        id: "post",
        header: ({ column }) => <DataGridColumnHeader title="Post" column={column} />,
        cell: ({ row }) => <PostCell row={row.original} />,
        minSize: 200,
        enableSorting: false,
        meta: { autoSize: true, headerClassName: "ps-(--frame-panel-px)", cellClassName: "ps-(--frame-panel-px)" },
      },
      {
        id: "meaning",
        header: ({ column }) => <DataGridColumnHeader title="What it means" column={column} />,
        cell: ({ row }) => <MeaningCell row={row.original} />,
        size: 230,
        enableSorting: false,
      },
      {
        id: "status",
        header: ({ column }) => <DataGridColumnHeader title="Status" column={column} />,
        cell: ({ row }) => (
          <Badge variant={row.original.tone}>
            <span aria-hidden className={`${DOT[row.original.tone]} size-1.5 rounded-full`} />
            {row.original.label}
          </Badge>
        ),
        size: 120,
        enableSorting: false,
      },
      {
        id: "time",
        header: ({ column }) => <DataGridColumnHeader title="Time" column={column} />,
        cell: ({ row }) => (
          <div className="flex flex-col gap-0.5 tabular-nums">
            <span className="text-sm">{dateTime(row.original.post.source_at)}</span>
            {row.original.call && <span className="text-muted-foreground text-xs">{untilText(endOfTradingDay(row.original.call.source.source_at), now)}</span>}
          </div>
        ),
        size: 150,
        enableSorting: false,
      },
      {
        id: "actions",
        header: () => null,
        cell: ({ row }) => {
          const call = row.original.call
          return (
            <div className="flex items-center justify-end gap-1" onClick={(event) => event.stopPropagation()}>
              {call && (
                <>
                  <Button type="button" variant="ghost" size="sm" onClick={() => onSkip(call)}>
                    Skip
                  </Button>
                  <Button type="button" variant="outline" size="sm" disabled={!canCopy} onClick={() => onCopy(call)} title={canCopy ? undefined : "Copying is off, so nothing can be placed yet."}>
                    {copyLabel(call)}
                  </Button>
                </>
              )}
              <DropdownMenu>
                <DropdownMenuTrigger render={<Button type="button" variant="ghost" size="icon-sm" aria-label={`Actions for post ${row.original.post.sequence}`} />}>
                  <EllipsisIcon aria-hidden="true" />
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" className="w-44">
                  <DropdownMenuItem onClick={() => navigate("activity", String(row.original.post.sequence))}>View in Activity</DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          )
        },
        size: 210,
        enableSorting: false,
        enableResizing: false,
        meta: { headerClassName: "pe-(--frame-panel-px)", cellClassName: "pe-(--frame-panel-px)" },
      },
    ],
    [canCopy, now, onCopy, onSkip],
  )

  const table = useTable({
    features: dataGridFeatures,
    data: shown,
    columns,
    getRowId: (row) => String(row.post.sequence),
    state: { pagination },
    onPaginationChange: setPagination,
  })

  // Pressing a row does what its first button does: review a waiting call, or open the post in Activity.
  const open = (row: PostTableRow) => (row.call && canCopy ? onCopy(row.call) : navigate("activity", String(row.post.sequence)))

  const empty =
    filter === "waiting" && query.trim() === "" ? (
      <EmptyState icon={CheckIcon} title="Nothing is waiting for you" action={{ label: "See Activity", onClick: () => navigate("activity") }} />
    ) : (
      "No posts match."
    )

  return (
    <section aria-label="Guru posts" className="flex flex-col gap-3">
      <DataGrid table={table} recordCount={shown.length} emptyMessage={empty} onRowClick={open}>
        <Frame className="w-full min-w-0">
          <FrameHeader className="flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex flex-col gap-px">
              <FrameTitle>Guru posts</FrameTitle>
              <FrameDescription>{calls.length === 0 ? "Nothing is waiting for you" : calls.length === 1 ? "1 waiting for you" : `${calls.length} waiting for you`}</FrameDescription>
            </div>
            <div className="flex w-full flex-col gap-2 sm:w-auto sm:flex-row sm:items-center sm:justify-end">
              {calls.length > 1 && (
                <Button type="button" variant="ghost" size="sm" onClick={onSkipAll}>
                  Skip all
                </Button>
              )}
              <Input
                type="search"
                value={query}
                onChange={(event) => {
                  setQuery(event.target.value)
                  resetPage()
                }}
                placeholder="Search posts"
                aria-label="Search posts"
                className="w-full sm:w-64"
              />
              <Select
                value={filter}
                onValueChange={(value) => {
                  const next = POST_FILTERS.find((option) => option.value === value)?.value
                  if (next) {
                    onFilterChange(next)
                    resetPage()
                  }
                }}
                items={POST_FILTERS}
              >
                <SelectTrigger className="w-full sm:w-36" aria-label="Filter posts">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent align="start" alignItemWithTrigger={false}>
                  <SelectGroup>
                    {POST_FILTERS.map((option) => (
                      <SelectItem key={option.value} value={option.value}>
                        {option.label}
                      </SelectItem>
                    ))}
                  </SelectGroup>
                </SelectContent>
              </Select>
            </div>
          </FrameHeader>

          <FramePanel className="p-0!">
            {posts.status === "loading" && (
              <div role="status" aria-label="Loading posts" className="flex flex-col gap-3 p-4">
                {Array.from({ length: 4 }, (_, i) => (
                  <Skeleton key={i} className="h-9 w-full" />
                ))}
              </div>
            )}
            {posts.status === "error" && (
              <div className="p-4">
                <RegionError title="Guru posts did not load" message={posts.error} onRetry={posts.retry} />
              </div>
            )}
            {posts.status === "ready" && rows.length === 0 && (
              <EmptyState icon={MessageSquareIcon} title="No posts yet" description="Posts from the gurus you copy appear here as they arrive." action={{ label: "Refresh", onClick: posts.retry }} className="p-5" />
            )}
            {posts.status === "ready" && rows.length > 0 && (
              <>
                <DataGridScrollArea>
                  <DataGridTable />
                </DataGridScrollArea>
                <Separator />
                <FrameFooter>
                  <DataGridPagination />
                </FrameFooter>
              </>
            )}
          </FramePanel>
        </Frame>
      </DataGrid>
      {recent && (
        <div className="text-muted-foreground flex items-baseline gap-3 py-1 text-sm">
          <span className="truncate">{recent.text ? `Skipped “${recent.text}”` : recent.sourceIds.length > 1 ? `Skipped ${recent.sourceIds.length} calls` : "Skipped"}</span>
          <Button type="button" size="xs" variant="ghost" onClick={onUndo}>
            Undo
          </Button>
        </div>
      )}
    </section>
  )
}
