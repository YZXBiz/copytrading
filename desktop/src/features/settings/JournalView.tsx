import { useEffect, useMemo, useState } from "react"
import { RefreshIcon } from "@/components/icons/RefreshIcon"
import { Search01Icon } from "@/components/icons/Search01Icon"
import { Tick02Icon } from "@/components/icons/Tick02Icon"
import { TriangleAlertIcon } from "@/components/icons/TriangleAlertIcon"
import type { DiagnosticsPage } from "../../../shared/contract"
import { Button } from "@/components/arc/button/button"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { SearchField } from "@/components/arc/search-field/search-field"
import SegmentedControl from "@/components/arc/segmented-control/segmented-control"
import { timeOfDay } from "@/lib/format"
import { SectionError } from "./SectionError"
import { SectionSkeleton } from "./SettingsSection"
import styles from "./settings.module.css"
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
  return <EmptyState title={text} description="The log fills in as the engine works." icon={<Search01Icon width={24} height={24} aria-hidden="true" />} />
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

  if (state.status === "loading") return <SectionSkeleton rows={4} label="Loading the log" />
  if (state.status === "error") return <SectionError title="The log did not load" message={state.error} onRetry={refresh} />
  if (entries.length === 0) return <EmptyLog text="Nothing logged yet" />
  return (
    <div className={styles.page}>
      <div className={styles.toolbar}>
        <SegmentedControl
          label="Filter the log"
          options={FILTERS.map((name) => ({ value: name, label: FILTER_TITLE[name], accessory: <span className={styles.valueMuted}>{entries.filter((e) => includes(name, e)).length}</span> }))}
          value={filter}
          onValueChange={(value) => setFilter(value as Filter)}
        />
        <div className={styles.toolbarEnd}>
          <div className={styles.search}>
            <SearchField label="Search the log" placeholder="Search" value={query} onValueChange={setQuery} />
          </div>
          <Button type="button" variant="ghost" size="sm" aria-label="Read the log again" onClick={refresh}>
            <RefreshIcon width={16} height={16} aria-hidden="true" />
          </Button>
        </div>
      </div>
      {visible.length === 0 ? (
        <EmptyLog text={needle ? `No records match “${query.trim()}”.` : FILTER_EMPTY[filter]} />
      ) : (
        <div className={styles.journal}>
          <ul className={styles.journalList} role="listbox" aria-label="Log records">
            {visible.map((row) => (
              <li key={row.id} role="presentation">
                <button type="button" role="option" aria-selected={row.id === entry?.id} className={styles.journalItem} style={{ width: "100%" }} data-problem={isProblem(row) || undefined} onClick={() => setSelected(row.id)}>
                  {isProblem(row) ? <TriangleAlertIcon width={16} height={16} aria-hidden="true" /> : <Tick02Icon width={16} height={16} aria-hidden="true" />}
                  <span style={{ display: "grid", minWidth: 0 }}>
                    <span className={styles.journalTop}>
                      <span>{title(row)}</span>
                      <span>{timeOfDay(row.at)}</span>
                    </span>
                    <span className={styles.journalSub}>{outcomeTitle(row)}</span>
                  </span>
                </button>
              </li>
            ))}
          </ul>
          {entry && <JournalDetail entry={entry} />}
        </div>
      )}
    </div>
  )
}
