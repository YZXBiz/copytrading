import type { AccountOverview } from "../../../shared/contract"
import { Badge } from "@/components/arc/badge/badge"
import { Button } from "@/components/arc/button/button"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import SortableDataTable from "@/components/arc/sortable-data-table/sortable-data-table"
import { parseDec } from "@/features/account/decimal"
import { dateTime, shares, signedMoney, signedPercent } from "@/lib/format"
import { usd } from "@/lib/quantity"
import styles from "./stock.module.css"

type Position = AccountOverview["positions"][number]
type Lot = Position["lots"][number]
type Row = { id: string; entry: string; shares: string; cost: string; gain: string; lot: Lot }

/** The shares of this stock CopyTrading bought, one row to a buy: when, how many are left, what each cost, what it is up or down, and a sale of that buy. */
export function StockLots({ symbol, position, price, onSell }: { symbol: string; position: Position | undefined; price: number | null; onSell: (lot: Lot) => void }) {
  const lots = (position?.lots ?? []).filter((lot) => (parseDec(lot.remaining_qty) ?? 0n) > 0n)
  const rows: Row[] = lots.map((lot) => ({
    id: lot.lot_id,
    entry: lot.bought_at ?? lot.posted_at ?? "",
    shares: lot.remaining_qty,
    cost: lot.average_price ?? "",
    gain: lot.unrealized_pl ?? "",
    lot,
  }))
  const columns = [
    {
      key: "entry",
      label: "Entry",
      sortable: false,
      render: (_: unknown, { lot }: Row) => (
        <span className={styles.lotEntry}>
          <span>{lot.bought_at ?? lot.posted_at ? dateTime((lot.bought_at ?? lot.posted_at)!) : "Date unknown"}</span>
          <span className={styles.muted}>{lot.guru_id ? `From ${lot.guru_id}'s post` : "From a post"}</span>
        </span>
      ),
    },
    { key: "shares", label: "Shares", sortable: false, numeric: true, render: (_: unknown, { lot }: Row) => `${shares(lot.remaining_qty)}` },
    { key: "cost", label: "Bought at", sortable: false, numeric: true, render: (_: unknown, { lot }: Row) => (lot.average_price ? usd(lot.average_price) : "No price") },
    {
      key: "gain",
      label: "Gain",
      sortable: false,
      numeric: true,
      render: (_: unknown, { lot }: Row) => {
        const entry = parseDec(lot.average_price)
        const held = Number(lot.remaining_qty)
        // The lot's own gain when the broker gave one; else the live price against what it cost.
        const amount = lot.unrealized_pl != null && Number.isFinite(Number(lot.unrealized_pl)) ? Number(lot.unrealized_pl) : price !== null && entry !== null ? (price - Number(lot.average_price)) * held : null
        const cost = entry !== null ? Number(lot.average_price) * held : 0
        if (amount === null) return <span className={styles.muted}>No price</span>
        return (
          <Badge tone={amount < 0 ? "danger" : "success"}>
            {signedMoney(amount)}
            {cost > 0 ? ` (${signedPercent(amount / cost)})` : ""}
          </Badge>
        )
      },
    },
    {
      key: "sell",
      label: "Sell",
      sortable: false,
      width: 110,
      render: (_: unknown, { lot }: Row) => (
        <span className={styles.rowAction}>
          <Button type="button" size="sm" variant="secondary" aria-label={`Sell this buy of ${symbol}`} onClick={() => onSell(lot)}>
            Sell
          </Button>
        </span>
      ),
    },
  ]
  return (
    <section className={styles.panel} aria-labelledby="lots-title">
      <header className={styles.panelHead}>
        <div>
          <h2 id="lots-title" className={styles.panelTitle}>
            Your {symbol}
          </h2>
          <p className={styles.panelMeta}>{rows.length === 0 ? "No shares held" : rows.length === 1 ? "1 buy held" : `${rows.length} buys held`}</p>
        </div>
      </header>
      {rows.length === 0 ? (
        <EmptyState title={`You hold no ${symbol}`} description="Shares CopyTrading buys in this account show up here, each with what it is up or down." />
      ) : (
        <SortableDataTable<Row> rows={rows} columns={columns} rowKey="id" caption={`Your ${symbol} buys`} />
      )}
    </section>
  )
}
