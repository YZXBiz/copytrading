import { useMemo } from "react"
import type { SourceActivity, SourceActivityPage } from "../../../shared/contract"
import { Badge } from "@/components/arc/badge/badge"
import { Button } from "@/components/arc/button/button"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import SortableDataTable from "@/components/arc/sortable-data-table/sortable-data-table"
import { RegionNote } from "@/features/account/RegionNote"
import { postRows } from "@/features/account/post-rows"
import { callPhrase } from "@/features/account/waiting"
import { readableText } from "@/features/activity/reading"
import { navigate } from "@/features/shell/route"
import { dateTime } from "@/lib/format"
import { type Loaded } from "@/lib/use-result"
import styles from "./stock.module.css"

const TONE = { "success-light": "success", "warning-light": "warning", "destructive-light": "danger", "info-light": "info", outline: "neutral" } as const

type Row = { id: string; date: string; call: string; status: string; post: SourceActivity; tone: keyof typeof TONE }

/** The guru's calls that name this stock, newest first, each with what became of it in this account and a way to its post. */
export function StockCalls({ symbol, accountId, posts, now, skipped }: { symbol: string; accountId: string; posts: Loaded<SourceActivityPage> & { retry: () => void }; now: Date; skipped: (sourceId: string) => boolean }) {
  const rows = useMemo<Row[]>(() => {
    if (posts.status !== "ready") return []
    const named = posts.data.items.filter((post) => [...(post.suggested ?? []), ...post.instructions].some((call) => call.symbol === symbol))
    return postRows(named, [], accountId, now, skipped).map(({ post, label, tone }) => {
      const call = [...(post.suggested ?? []), ...post.instructions].find((c) => c.symbol === symbol)!
      return { id: String(post.sequence), date: post.source_at, call: callPhrase(call), status: label, post, tone }
    })
  }, [posts, symbol, accountId, now, skipped])

  const columns = [
    { key: "date", label: "Date", sortable: false, width: 150, render: (_: unknown, { post }: Row) => <span className={styles.nowrap}>{dateTime(post.source_at)}</span> },
    {
      key: "call",
      label: "Call",
      sortable: false,
      render: (_: unknown, { call, post }: Row) => (
        <span className={styles.callCell}>
          <span>{call}</span>
          {/* The post is untrusted Discord text: rendered as text, never as HTML. */}
          <span className={styles.callText}>{readableText(post) ? `“${readableText(post)}”` : "A picture"}</span>
        </span>
      ),
    },
    { key: "status", label: "Status", sortable: false, width: 130, render: (_: unknown, { status, tone }: Row) => <Badge tone={TONE[tone]} dot>{status}</Badge> },
    {
      key: "open",
      label: "Post",
      sortable: false,
      width: 110,
      render: (_: unknown, { post }: Row) => (
        <span className={styles.rowAction}>
          <Button type="button" size="sm" variant="ghost" onClick={() => navigate("activity", String(post.sequence))}>
            View post
          </Button>
        </span>
      ),
    },
  ]
  return (
    <section className={styles.panel} aria-labelledby="calls-title">
      <header className={styles.panelHead}>
        <div>
          <h2 id="calls-title" className={styles.panelTitle}>
            Guru calls on {symbol}
          </h2>
          <p className={styles.panelMeta}>{rows.length === 1 ? "1 call" : `${rows.length} calls`}</p>
        </div>
      </header>
      {posts.status === "loading" && <Skeleton label="Loading guru calls" lines={3} />}
      {posts.status === "error" && <RegionNote title="Guru calls did not load" message={posts.error} onRetry={posts.retry} />}
      {posts.status === "ready" && rows.length === 0 && <EmptyState title={`No calls on ${symbol}`} description="When the guru you copy posts a call on this stock, it appears here." />}
      {posts.status === "ready" && rows.length > 0 && <SortableDataTable<Row> rows={rows} columns={columns} rowKey="id" caption={`Guru calls on ${symbol}`} />}
    </section>
  )
}
