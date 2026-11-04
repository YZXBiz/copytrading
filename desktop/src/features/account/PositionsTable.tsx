import { useMemo } from "react"
import { type ColumnDef, useTable } from "@tanstack/react-table"
import { ChevronDownIcon, PackageOpenIcon } from "lucide-react"
import type { AccountOverview } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { DataGrid, type DataGridFeatures, dataGridFeatures } from "@/components/reui/data-grid/data-grid"
import { DataGridColumnHeader } from "@/components/reui/data-grid/data-grid-column-header"
import { DataGridScrollArea } from "@/components/reui/data-grid/data-grid-scroll-area"
import { DataGridTable } from "@/components/reui/data-grid/data-grid-table"
import { Meta } from "@/components/meta"
import { Frame, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { Button } from "@/components/ui/button"
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import { money, monthDay, shares, signedMoney, signedPercent } from "@/lib/format"
import { parseDec } from "./decimal"
import { heldPositions, holdingNote } from "./model"
import { sharesText } from "@/lib/quantity"

type Position = AccountOverview["positions"][number]

const RIGHT = { headerClassName: "text-end [&>div]:justify-end", cellClassName: "text-end tabular-nums" }

type Lot = Position["lots"][number]

/** Lots with shares left to sell. */
export const sellable = (position: Position) => position.lots.filter((lot) => (parseDec(lot.remaining_qty) ?? 0n) > 0n)

/** "赵哥 · Oct 22 · 2.052 shares": which buy a lot is. */
const lotLabel = (position: Position, lot: Lot) =>
  [lot.guru_id ?? "A post", lot.posted_at && monthDay(lot.posted_at), sharesText(parseDec(lot.remaining_qty) ?? 0n, position.symbol)].filter(Boolean).join(" · ")

/** Sell one lot of the stock: one Sell button, or a menu of the lots when several buys make it up. */
function SellCell({ position, onSell }: { position: Position; onSell: (position: Position, lot: Lot) => void }) {
  const lots = sellable(position)
  if (lots.length === 0) return null
  if (lots.length === 1) {
    return (
      <Button type="button" size="xs" variant="ghost" aria-label={`Sell ${lotLabel(position, lots[0]!)}`} onClick={() => onSell(position, lots[0]!)}>
        Sell
      </Button>
    )
  }
  return (
    <DropdownMenu>
      <DropdownMenuTrigger render={<Button type="button" size="xs" variant="ghost" aria-label={`Sell ${position.symbol}: choose a buy`} />}>
        Sell <ChevronDownIcon aria-hidden />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-auto">
        {lots.map((lot) => (
          <DropdownMenuItem key={lot.lot_id} onClick={() => onSell(position, lot)}>
            {lotLabel(position, lot)}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

const columns = (onSell: (position: Position, lot: Lot) => void): ColumnDef<DataGridFeatures, Position>[] => [
  {
    accessorKey: "symbol",
    header: ({ column }) => <DataGridColumnHeader title="Stock" column={column} />,
    cell: ({ row }) => (
      <div className="flex flex-col">
        <span className="font-medium">{row.original.symbol}</span>
        <Meta className="text-muted-foreground text-xs" text={holdingNote(row.original) ?? ""} />
      </div>
    ),
  },
  { accessorKey: "owned_qty", header: ({ column }) => <DataGridColumnHeader title="Shares" column={column} />, cell: ({ row }) => shares(row.original.owned_qty), meta: RIGHT },
  { accessorKey: "avg_entry_price", header: ({ column }) => <DataGridColumnHeader title="Avg cost" column={column} />, cell: ({ row }) => money(row.original.avg_entry_price), size: 110, meta: RIGHT },
  { accessorKey: "current_price", header: ({ column }) => <DataGridColumnHeader title="Price" column={column} />, cell: ({ row }) => money(row.original.current_price), size: 110, meta: RIGHT },
  { accessorKey: "market_value", header: ({ column }) => <DataGridColumnHeader title="Value" column={column} />, cell: ({ row }) => money(row.original.market_value), size: 110, meta: RIGHT },
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
  { id: "sell", header: () => <span className="sr-only">Sell</span>, cell: ({ row }) => <SellCell position={row.original} onSell={onSell} />, size: 90, meta: RIGHT },
]

export function PositionsTable({
  account,
  onRefresh,
  onSell,
}: {
  account: AccountOverview
  onRefresh: () => void
  onSell: (position: Position, lot: Lot) => void
}) {
  const data = useMemo(() => heldPositions(account), [account])
  const cols = useMemo(() => columns(onSell), [onSell])
  const table = useTable({ features: dataGridFeatures, data, columns: cols, getRowId: (row) => row.symbol })
  return (
    <Frame spacing="sm">
      <FrameHeader>
        <FrameTitle>Positions</FrameTitle>
      </FrameHeader>
      <FramePanel className="p-0">
        {data.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <PackageOpenIcon />
              </EmptyMedia>
              <EmptyTitle>No stocks bought yet</EmptyTitle>
              <EmptyDescription>Shares CopyTrading buys show up here.</EmptyDescription>
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
