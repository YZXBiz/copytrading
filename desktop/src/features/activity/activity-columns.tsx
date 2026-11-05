import type { DataColumn } from "@/components/arc/sortable-data-table/sortable-data-table"
import { monthDay, timeOfDay } from "@/lib/format"
import { OutcomeBadge } from "./OutcomeBadge"
import { PostMark } from "./PostMark"
import { type ActivityRow } from "./activity-rows"
import styles from "./activity.module.css"

/** One table row: the values the columns sort by, and the row they are read from. */
export interface PostTableRow extends Record<string, unknown> {
  id: string
  /** The post's sequence, padded so the columns sort it as a number. */
  time: string
  guru: string
  status: string
  row: ActivityRow
}

export const tableRow = (row: ActivityRow): PostTableRow => ({ id: String(row.post.sequence), time: String(row.post.sequence).padStart(12, "0"), guru: row.guru, status: row.label, row })

/** What each account did with the post: a line each, two at most. */
function AccountsCell({ row }: { row: ActivityRow }) {
  if (row.accounts.length === 0) return <span className={styles.none}>None</span>
  const shown = row.accounts.slice(0, 2)
  return (
    <div className={styles.accounts}>
      {shown.map((a) => (
        <span key={a.accountId}>
          {row.accounts.length > 1 && <b>{a.accountId}</b>}
          <i>{a.summary || "Nothing yet"}</i>
        </span>
      ))}
      {row.accounts.length > shown.length && <small>+{row.accounts.length - shown.length} more</small>}
    </div>
  )
}

export function activityColumns({ onOpen }: { onOpen: (row: ActivityRow) => void }): DataColumn<PostTableRow>[] {
  return [
    {
      key: "time",
      label: "Time",
      sortable: true,
      width: 112,
      render: (_, { row }) => (
        <div className={styles.when}>
          <span>{timeOfDay(row.post.source_at)}</span>
          <span>{monthDay(row.post.source_at)}</span>
        </div>
      ),
    },
    {
      key: "guru",
      label: "Guru",
      sortable: true,
      width: 140,
      render: (_, { row }) => (
        <div className={styles.who}>
          <span aria-hidden="true">{[...row.guru][0]}</span>
          <span>{row.guru}</span>
        </div>
      ),
    },
    {
      key: "post",
      label: "Post",
      width: 260,
      render: (_, { row }) => (
        <div className={styles.postCell}>
          <span className={styles.mark} aria-hidden="true">
            <PostMark symbol={row.symbol} />
          </span>
          <button type="button" className={styles.open} aria-haspopup="dialog" data-sequence={row.post.sequence} onClick={() => onOpen(row)}>
            {row.said}
          </button>
        </div>
      ),
    },
    { key: "meaning", label: "What it means", width: 200, render: (_, { row }) => <span className={styles.clamp}>{row.meaning}</span> },
    { key: "status", label: "Status", sortable: true, width: 140, render: (_, { row }) => <OutcomeBadge title={row.label} tone={row.tone} /> },
    { key: "accounts", label: "In each account", width: 220, render: (_, { row }) => <AccountsCell row={row} /> },
  ]
}
