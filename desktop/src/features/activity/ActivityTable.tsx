import { useCallback, useMemo, useState } from "react"
import { FilterIcon, LandmarkIcon, SearchIcon, XIcon } from "lucide-react"
import { type PaginationState, type SortingState, useTable } from "@tanstack/react-table"
import { DataGrid, dataGridFeatures } from "@/components/reui/data-grid/data-grid"
import { DataGridPagination } from "@/components/reui/data-grid/data-grid-pagination"
import { DataGridScrollArea } from "@/components/reui/data-grid/data-grid-scroll-area"
import { DataGridTable } from "@/components/reui/data-grid/data-grid-table"
import { Frame, FrameDescription, FrameFooter, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { Button } from "@/components/ui/button"
import { InputGroup, InputGroupAddon, InputGroupButton, InputGroupInput } from "@/components/ui/input-group"
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Spinner } from "@/components/ui/spinner"
import { navigate } from "@/features/shell/route"
import { type ActivityRow, matches } from "./activity-rows"
import { activityColumns } from "./activity-columns"
import { BUCKETS, BUCKET_LABEL, type Bucket } from "./post-bucket"

export type PostFilter = "all" | Bucket
const FILTERS: { value: PostFilter; label: string }[] = [{ value: "all", label: "All posts" }, ...BUCKETS.map((b) => ({ value: b, label: BUCKET_LABEL[b] }))]

/** dashboard-7's Order Queue: a Frame with a search, a filter and a DataGrid with pagination, wired to the guru posts. A row opens the post. */
export function ActivityTable({
  rows,
  accountIds,
  accountId,
  onAccountChange,
  filter,
  onFilterChange,
  older,
}: {
  rows: ActivityRow[]
  accountIds: string[]
  accountId: string | null
  onAccountChange: (id: string | null) => void
  filter: PostFilter
  onFilterChange: (filter: PostFilter) => void
  /** Reads posts older than the ones loaded, when there are some. */
  older: { loading: boolean; show: () => void } | null
}) {
  const [query, setQuery] = useState("")
  const [pagination, setPagination] = useState<PaginationState>({ pageIndex: 0, pageSize: 10 })
  const [sorting, setSorting] = useState<SortingState>([{ id: "time", desc: true }])
  const resetPagination = () => setPagination((current) => (current.pageIndex === 0 ? current : { ...current, pageIndex: 0 }))

  const shown = useMemo(() => rows.filter((row) => (accountId === null || row.accounts.length > 0) && (filter === "all" || row.bucket === filter) && matches(row, query)), [rows, filter, query, accountId])
  const open = useCallback((row: ActivityRow) => navigate("activity", String(row.post.sequence)), [])
  const columns = useMemo(() => activityColumns({ onOpen: open }), [open])

  const pageCount = Math.max(Math.ceil(shown.length / pagination.pageSize), 1)
  const pageIndex = Math.min(pagination.pageIndex, pageCount - 1)

  const table = useTable({
    features: dataGridFeatures,
    data: shown,
    columns,
    pageCount,
    state: { pagination: { ...pagination, pageIndex }, sorting },
    getRowId: (row) => String(row.post.sequence),
    onPaginationChange: setPagination,
    onSortingChange: setSorting,
  })

  const choices = [{ value: "all", label: "All accounts" }, ...accountIds.map((id) => ({ value: id, label: id }))]

  return (
    <DataGrid
      table={table}
      recordCount={shown.length}
      emptyMessage="No posts match the current view."
      onRowClick={open}
      tableLayout={{ dense: true, rowBorder: true, headerSticky: false, columnsVisibility: false, columnsResizable: true, columnsMovable: false, width: "fixed" }}
      tableClassNames={{ bodyRow: "[&>td]:h-16" }}
    >
      <Frame className="min-w-0">
        <FrameHeader className="flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
          <div className="flex flex-col gap-px">
            <FrameTitle>Guru posts</FrameTitle>
            <FrameDescription>
              {shown.length} {shown.length === 1 ? "post" : "posts"}
              {older ? " so far" : ""}
            </FrameDescription>
          </div>
          <div className="flex w-full flex-col gap-2 sm:flex-row lg:w-auto">
            <InputGroup className="w-full sm:min-w-56 lg:w-64">
              <InputGroupAddon>
                <SearchIcon aria-hidden="true" />
              </InputGroupAddon>
              <InputGroupInput
                value={query}
                onChange={(event) => {
                  setQuery(event.target.value)
                  resetPagination()
                }}
                placeholder="Search posts"
                aria-label="Search posts"
              />
              {query.length > 0 && (
                <InputGroupAddon align="inline-end">
                  <InputGroupButton
                    size="icon-xs"
                    aria-label="Clear search"
                    onClick={() => {
                      setQuery("")
                      resetPagination()
                    }}
                  >
                    <XIcon aria-hidden="true" />
                  </InputGroupButton>
                </InputGroupAddon>
              )}
            </InputGroup>
            <Select
              items={FILTERS}
              value={filter}
              onValueChange={(value) => {
                const next = FILTERS.find((option) => option.value === value)?.value
                if (next) {
                  onFilterChange(next)
                  resetPagination()
                }
              }}
            >
              <SelectTrigger size="sm" className="w-full sm:w-36" aria-label="Filter posts">
                <FilterIcon className="text-muted-foreground size-4" aria-hidden="true" />
                <SelectValue />
              </SelectTrigger>
              <SelectContent align="end" alignItemWithTrigger={false}>
                <SelectGroup>
                  {FILTERS.map((option) => (
                    <SelectItem key={option.value} value={option.value}>
                      {option.label}
                    </SelectItem>
                  ))}
                </SelectGroup>
              </SelectContent>
            </Select>
            {accountIds.length > 1 && (
              <Select
                items={choices}
                value={accountId ?? "all"}
                onValueChange={(next) => {
                  if (next) {
                    onAccountChange(next === "all" ? null : next)
                    resetPagination()
                  }
                }}
              >
                <SelectTrigger size="sm" className="w-full sm:w-40" aria-label="Account">
                  <LandmarkIcon className="text-muted-foreground size-4" aria-hidden="true" />
                  <SelectValue />
                </SelectTrigger>
                <SelectContent align="end" alignItemWithTrigger={false}>
                  <SelectGroup>
                    {choices.map((choice) => (
                      <SelectItem key={choice.value} value={choice.value}>
                        {choice.label}
                      </SelectItem>
                    ))}
                  </SelectGroup>
                </SelectContent>
              </Select>
            )}
            {older && (
              <Button type="button" variant="outline" size="sm" onClick={older.show} disabled={older.loading}>
                {older.loading && <Spinner data-icon="inline-start" />}
                Show older
              </Button>
            )}
          </div>
        </FrameHeader>
        <FramePanel className="p-0!">
          <DataGridScrollArea>
            <DataGridTable />
          </DataGridScrollArea>
        </FramePanel>
        <FrameFooter>
          <DataGridPagination sizes={[5, 10, 20]} info="{from} - {to} of {count} posts" className="py-0" />
        </FrameFooter>
      </Frame>
    </DataGrid>
  )
}
