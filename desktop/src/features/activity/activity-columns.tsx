import { type ColumnDef } from "@tanstack/react-table"
import { type DataGridFeatures } from "@/components/reui/data-grid/data-grid"
import { DataGridColumnHeader } from "@/components/reui/data-grid/data-grid-column-header"
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import { monthDay, timeOfDay } from "@/lib/format"
import { OutcomeBadge } from "./OutcomeBadge"
import { PostTile } from "./PostTile"
import { type ActivityRow } from "./activity-rows"

type OpenPost = (row: ActivityRow, origin: HTMLElement) => void


/** What each account did with the post: a line each, two at most. */
function AccountsCell({ row }: { row: ActivityRow }) {
  if (row.accounts.length === 0) return <span className="text-muted-foreground text-sm">—</span>
  const shown = row.accounts.slice(0, 2)
  return (
    <div className="min-w-0">
      {shown.map((a) => (
        <div key={a.accountId} className="flex min-w-0 items-baseline gap-1.5 text-xs">
          {row.accounts.length > 1 && <span className="text-muted-foreground max-w-24 shrink-0 truncate">{a.accountId}</span>}
          <span className="truncate font-medium">{a.summary || "—"}</span>
        </div>
      ))}
      {row.accounts.length > shown.length && <div className="text-muted-foreground text-xs">+{row.accounts.length - shown.length} more</div>}
    </div>
  )
}

export function activityColumns({ onOpen }: { onOpen: OpenPost }): ColumnDef<DataGridFeatures, ActivityRow>[] {
  return [
    {
      id: "time",
      accessorFn: (row) => row.post.sequence,
      header: ({ column }) => <DataGridColumnHeader column={column} visibility={true} />,
      cell: ({ row }) => (
        <div className="min-w-0">
          <div className="text-sm font-medium tabular-nums">{timeOfDay(row.original.post.source_at)}</div>
          <div className="text-muted-foreground text-xs tabular-nums">{monthDay(row.original.post.source_at)}</div>
        </div>
      ),
      size: 96,
      enableSorting: true,
      enableHiding: false,
      enableResizing: true,
      meta: { headerTitle: "Time", cellClassName: "ps-4!", headerClassName: "ps-4!" },
    },
    {
      id: "guru",
      accessorFn: (row) => row.guru,
      header: ({ column }) => <DataGridColumnHeader column={column} visibility={true} />,
      cell: ({ row }) => (
        <div className="flex min-w-0 items-center gap-2">
          <Avatar size="sm" aria-hidden="true">
            <AvatarFallback className="text-xs">{Array.from(row.original.guru)[0]}</AvatarFallback>
          </Avatar>
          <span className="truncate text-sm font-medium">{row.original.guru}</span>
        </div>
      ),
      size: 120,
      minSize: 100,
      enableSorting: true,
      enableHiding: false,
      enableResizing: true,
      meta: { headerTitle: "Guru" },
    },
    {
      id: "post",
      header: ({ column }) => <DataGridColumnHeader column={column} visibility={true} />,
      cell: ({ row }) => (
        <div className="flex min-w-0 items-center gap-2.5">
          <PostTile symbol={row.original.symbol} />
          <button
            type="button"
            className="hover:text-primary block min-w-0 truncate text-left text-sm font-medium underline-offset-2 transition-colors hover:underline"
            aria-label={`Open the post by ${row.original.guru}`}
            aria-haspopup="dialog"
            onClick={(event) => {
              event.stopPropagation()
              onOpen(row.original, event.currentTarget)
            }}
          >
            {row.original.said}
          </button>
        </div>
      ),
      size: 220,
      minSize: 180,
      enableSorting: false,
      enableHiding: false,
      enableResizing: true,
      meta: { headerTitle: "Post", autoSize: true },
    },
    {
      id: "meaning",
      header: ({ column }) => <DataGridColumnHeader column={column} visibility={true} />,
      cell: ({ row }) => <div className="truncate text-sm">{row.original.meaning}</div>,
      size: 196,
      minSize: 140,
      enableSorting: false,
      enableHiding: false,
      enableResizing: true,
      meta: { headerTitle: "What it means" },
    },
    {
      id: "status",
      accessorFn: (row) => row.label,
      header: ({ column }) => <DataGridColumnHeader column={column} visibility={true} />,
      cell: ({ row }) => <OutcomeBadge title={row.original.label} tone={row.original.tone} />,
      size: 128,
      enableSorting: true,
      enableHiding: false,
      enableResizing: true,
      meta: { headerTitle: "Status" },
    },
    {
      id: "accounts",
      header: ({ column }) => <DataGridColumnHeader column={column} visibility={true} />,
      cell: ({ row }) => <AccountsCell row={row.original} />,
      size: 210,
      minSize: 170,
      enableSorting: false,
      enableHiding: false,
      enableResizing: true,
      meta: { headerTitle: "In each account", cellClassName: "pe-4!", headerClassName: "pe-4!" },
    },
  ]
}
