import { useEffect, useMemo, useState } from "react"
import { CheckIcon, RefreshCwIcon, SearchIcon, TriangleAlertIcon } from "lucide-react"
import type { DiagnosticsPage } from "../../../shared/contract"
import { RegionError } from "@/components/region-error"
import { Button } from "@/components/ui/button"
import { Frame, FramePanel } from "@/components/reui/frame"
import { Empty, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group"
import { Item, ItemContent, ItemGroup, ItemMedia, ItemTitle } from "@/components/ui/item"
import { Skeleton } from "@/components/ui/skeleton"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { timeOfDay } from "@/lib/format"
import { cn } from "cn"
import { JournalDetail } from "./JournalDetail"
import { FILTERS, FILTER_EMPTY, FILTER_TITLE, type Filter, includes, isProblem, outcomeTitle, searchText, title } from "./journal"

const REFRESH_MS = 5000

type State = { status: "loading" } | { status: "error"; error: string } | { status: "ready"; page: DiagnosticsPage }

/** The journal, read again every few seconds while open. A failed read keeps what was already shown. */
function useJournal(onBytes: (bytes: number) => void) {
  const [state, setState] = useState<State>({ status: "loading" })
  const [reload, setReload] = useState(0)
  useEffect(() => {
    let current = true
    const read = () =>
      window.copytrading.read.readDiagnostics().then((result) => {
        if (!current) return
        if (result.ok) {
          setState({ status: "ready", page: result.value })
          onBytes(result.value.bytes)
        } else setState((was) => (was.status === "ready" ? was : { status: "error", error: result.error }))
      })
    void read()
    const timer = setInterval(read, REFRESH_MS)
    return () => {
      current = false
      clearInterval(timer)
    }
  }, [reload, onBytes])
  return { state, refresh: () => (setState({ status: "loading" }), setReload((n) => n + 1)) }
}

function EmptyLog({ text }: { text: string }) {
  return (
    <Frame>
      <FramePanel>
        <Empty className="min-h-40">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <SearchIcon />
            </EmptyMedia>
            <EmptyTitle>{text}</EmptyTitle>
            <EmptyDescription>The log fills in as the engine works.</EmptyDescription>
          </EmptyHeader>
        </Empty>
      </FramePanel>
    </Frame>
  )
}

/** The filters and the two panes in their real layout while the log is read. */
function JournalSkeleton() {
  return (
    <div role="status" aria-label="Loading the log" className="flex flex-col gap-3">
      <div className="flex items-center gap-3">
        <Skeleton className="h-8 w-72" />
        <Skeleton className="ml-auto h-8 w-48" />
      </div>
      <div className="grid grid-cols-[minmax(16rem,20rem)_1fr] gap-4">
        <Skeleton className="h-72 w-full" />
        <Skeleton className="h-72 w-full" />
      </div>
    </div>
  )
}

/** The engine's local log, read straight from disk: searchable, filterable, and readable while the engine is stopped. */
export function JournalView({ onBytes }: { onBytes: (bytes: number) => void }) {
  const { state, refresh } = useJournal(onBytes)
  const [filter, setFilter] = useState<Filter>("all")
  const [query, setQuery] = useState("")
  const [selected, setSelected] = useState<string | null>(null)
  const entries = state.status === "ready" ? state.page.entries : []
  const needle = query.trim().toLowerCase()
  const visible = useMemo(() => entries.filter((e) => includes(filter, e) && (!needle || searchText(e).includes(needle))), [entries, filter, needle])
  const entry = visible.find((e) => e.id === selected) ?? visible[0]

  if (state.status === "loading") return <JournalSkeleton />
  if (state.status === "error") return <RegionError title="The log did not load" message={state.error} onRetry={refresh} />
  if (entries.length === 0) return <EmptyLog text="Nothing logged yet" />
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-3">
        <Tabs value={filter} onValueChange={(value) => setFilter(value as Filter)}>
          <TabsList variant="line">
            {FILTERS.map((name) => (
              <TabsTrigger key={name} value={name}>
                {FILTER_TITLE[name]} <span className="text-muted-foreground tabular-nums">{entries.filter((e) => includes(name, e)).length}</span>
              </TabsTrigger>
            ))}
          </TabsList>
        </Tabs>
        <InputGroup className="ml-auto w-48">
          <InputGroupAddon>
            <SearchIcon aria-hidden />
          </InputGroupAddon>
          <InputGroupInput aria-label="Search the log" placeholder="Search" value={query} onChange={(event) => setQuery(event.target.value)} />
        </InputGroup>
        <Button type="button" variant="ghost" size="icon" aria-label="Read the log again" onClick={refresh}>
          <RefreshCwIcon />
        </Button>
      </div>
      {visible.length === 0 ? (
        <EmptyLog text={needle ? `No records match “${query.trim()}”.` : FILTER_EMPTY[filter]} />
      ) : (
        <div className="grid min-h-0 grid-cols-[minmax(16rem,20rem)_1fr] items-start gap-4">
          <Frame dense spacing="sm" className="min-w-0">
            <FramePanel className="p-0!">
              <ItemGroup className="max-h-[32rem] gap-0 overflow-y-auto" role="listbox" aria-label="Log records">
            {visible.map((row) => (
              <Item
                key={row.id}
                size="xs"
                role="option"
                aria-selected={row.id === entry?.id}
                tabIndex={0}
                className={cn("cursor-pointer rounded-none border-0 [content-visibility:auto] [contain-intrinsic-size:auto_44px]", row.id === entry?.id && "bg-muted")}
                onClick={() => setSelected(row.id)}
                onKeyDown={(event) => (event.key === "Enter" || event.key === " ") && (event.preventDefault(), setSelected(row.id))}
              >
                <ItemMedia variant="icon">
                  {isProblem(row) ? <TriangleAlertIcon className="text-warning-foreground dark:text-warning" aria-hidden /> : <CheckIcon className="text-muted-foreground" aria-hidden />}
                </ItemMedia>
                <ItemContent>
                  <ItemTitle className="w-full justify-between">
                    <span className="truncate">{title(row)}</span>
                    <span className="text-muted-foreground text-xs font-normal tabular-nums">{timeOfDay(row.at)}</span>
                  </ItemTitle>
                  <span className="text-muted-foreground text-xs">{outcomeTitle(row)}</span>
                </ItemContent>
              </Item>
            ))}
              </ItemGroup>
            </FramePanel>
          </Frame>
          {entry && <JournalDetail entry={entry} />}
        </div>
      )}
    </div>
  )
}
