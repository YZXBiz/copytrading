import { useMemo } from "react"
import { type ColumnDef, useTable } from "@tanstack/react-table"
import { PackageOpenIcon } from "lucide-react"
import type { AccountOverview } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { DataGrid, type DataGridFeatures, dataGridFeatures } from "@/components/reui/data-grid/data-grid"
import { DataGridColumnHeader } from "@/components/reui/data-grid/data-grid-column-header"
import { DataGridScrollArea } from "@/components/reui/data-grid/data-grid-scroll-area"
import { DataGridTable } from "@/components/reui/data-grid/data-grid-table"
import { Frame, FrameDescription, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { Button } from "@/components/ui/button"
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { money, shares, signedMoney, signedPercent } from "@/lib/format"
import { heldPositions, holdingNote } from "./model"

type Position = AccountOverview["positions"][number]

const RIGHT = { headerClassName: "text-end [&>div]:justify-end", cellClassName: "text-end tabular-nums" }

const columns: ColumnDef<DataGridFeatures, Position>[] = [
  {
    accessorKey: "symbol",
    header: ({ column }) => <DataGridColumnHeader title="Stock" column={column} />,
    cell: ({ row }) => (
      <div className="flex flex-col">
        <span className="font-medium">{row.original.symbol}</span>
        <span className="text-muted-foreground text-xs">{holdingNote(row.original)}</span>
      </div>
    ),
  },
  { accessorKey: "owned_qty", header: ({ column }) => <DataGridColumnHeader title="Shares" column={column} />, cell: ({ row }) => shares(row.original.owned_qty), meta: RIGHT },
  { accessorKey: "avg_entry_price", header: ({ column }) => <DataGridColumnHeader title="Avg cost" column={column} />, cell: ({ row }) => money(row.original.avg_entry_price), meta: RIGHT },
  { accessorKey: "current_price", header: ({ column }) => <DataGridColumnHeader title="Price" column={column} />, cell: ({ row }) => money(row.original.current_price), meta: RIGHT },
  { accessorKey: "market_value", header: ({ column }) => <DataGridColumnHeader title="Value" column={column} />, cell: ({ row }) => money(row.original.market_value), meta: RIGHT },
  {
    accessorKey: "unrealized_pl",
    header: ({ column }) => <DataGridColumnHeader title="Gain" column={column} />,
    cell: ({ row }) => {
      const pl = Number(row.original.unrealized_pl ?? 0)
      return (
        <div className="flex items-center justify-end gap-2">
          <span>{signedMoney(pl)}</span>
          <Badge variant={pl < 0 ? "destructive-light" : "success-light"}>{signedPercent(row.original.unrealized_plpc)}</Badge>
        </div>
      )
    },
    meta: RIGHT,
  },
]

export function PositionsTable({ account, onRefresh }: { account: AccountOverview; onRefresh: () => void }) {
  const data = useMemo(() => heldPositions(account), [account])
  const table = useTable({ features: dataGridFeatures, data, columns, getRowId: (row) => row.symbol })
  return (
    <Frame spacing="sm">
      <FrameHeader>
        <FrameTitle>Positions</FrameTitle>
        <FrameDescription>Bought by CopyTrading</FrameDescription>
      </FrameHeader>
      <FramePanel className="p-0">
        {data.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <PackageOpenIcon />
              </EmptyMedia>
              <EmptyTitle>No stocks bought yet</EmptyTitle>
              <EmptyDescription>Shares CopyTrading buys for this account show up here.</EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Button type="button" size="sm" variant="outline" onClick={onRefresh}>
                Refresh
              </Button>
            </EmptyContent>
          </Empty>
        ) : (
          <DataGrid
            table={table}
            recordCount={data.length}
            tableLayout={{ dense: true, headerBackground: true }}
            tableClassNames={{ base: "min-w-[720px]" }}
          >
            <DataGridScrollArea>
              <DataGridTable />
            </DataGridScrollArea>
          </DataGrid>
        )}
      </FramePanel>
    </Frame>
  )
}
