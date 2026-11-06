import { useState } from "react"
import { ArrowDown02Icon } from "@/components/icons/ArrowDown02Icon"
import { ArrowUp02Icon } from "@/components/icons/ArrowUp02Icon"
import type { AccountOverview, Bar } from "../../../shared/contract"
import { AnimatedCounter } from "@/components/arc/animated-counter/animated-counter"
import { Badge } from "@/components/arc/badge/badge"
import { DropdownMenu } from "@/components/arc/dropdown-menu/dropdown-menu"
import { EmptyState } from "@/components/arc/empty-state/empty-state"
import { Button } from "@/components/arc/button/button"
import SegmentedControl from "@/components/arc/segmented-control/segmented-control"
import { Tooltip } from "@/components/arc/tooltip/tooltip"
import { TICK_MS, liveRow } from "@/features/live/live"
import { useLivePrices } from "@/features/live/use-live-prices"
import { SymbolMark, TickerLink } from "@/features/stock/TickerLink"
import { monthDay, shares, signedPercent } from "@/lib/format"
import { sharesText } from "@/lib/quantity"
import styles from "./account.module.css"
import { parseDec } from "./decimal"
import { HOLDINGS_SORTS, type HoldingsSort, sortHoldings } from "./holdings-sort"
import { heldPositions } from "./model"
import { PositionSparkline } from "./PositionSparkline"
import { stopLine } from "./stops"
import { useBars } from "./use-bars"

type Position = AccountOverview["positions"][number]
type Lot = Position["lots"][number]

/** Lots with shares left to sell. */
export const sellable = (position: Position) => position.lots.filter((lot) => (parseDec(lot.remaining_qty) ?? 0n) > 0n)

/** "赵哥, Oct 22, 2.052 shares": which buy a lot is. */
export const lotLabel = (position: Position, lot: Lot) =>
  [lot.guru_id ?? "A post", lot.posted_at && monthDay(lot.posted_at), sharesText(parseDec(lot.remaining_qty) ?? 0n, position.symbol)].filter(Boolean).join(", ")

function Row({ accountId, position, livePrice, bars, onSell }: { accountId: string; position: Position; livePrice: number | null; bars: Bar[] | undefined; onSell: (position: Position, lot: Lot) => void }) {
  const row = liveRow(position, livePrice)
  const down = (row.gain ?? 0) < 0
  const lots = sellable(position)
  const value = row.value === null ? null : Number(row.value.toFixed(2))
  const stop = stopLine(position)
  return (
    <li className={styles.holding}>
      <SymbolMark symbol={position.symbol} />
      <div className={styles.holdingName}>
        <TickerLink symbol={position.symbol} accountId={accountId} className={styles.holdingLink} />
        <span className={styles.holdingShares}>{`${shares(position.owned_qty)} shares`}</span>
        {stop && <span className={styles.holdingShares}>{stop}</span>}
      </div>
      <PositionSparkline bars={bars} />
      <div className={styles.holdingValue}>
        {value === null ? (
          <span className={styles.muted}>No price</span>
        ) : livePrice !== null ? (
          <Tooltip content={`The price shown is live, read every ${TICK_MS / 1000} seconds`} side="top">
            <span>
              <AnimatedCounter value={value} prefix="$" decimals={2} />
            </span>
          </Tooltip>
        ) : (
          <AnimatedCounter value={value} prefix="$" decimals={2} />
        )}
        <Badge tone={down ? "danger" : "success"} icon={down ? <ArrowDown02Icon width={16} height={16} /> : <ArrowUp02Icon width={16} height={16} />}>
          {signedPercent(row.gainFraction)}
        </Badge>
      </div>
      <div className={styles.holdingSell}>
        {lots.length > 0 && (
          <DropdownMenu label="Sell" items={lots.map((lot) => ({ label: `Sell ${lotLabel(position, lot)}`, onSelect: () => onSell(position, lot) }))} />
        )}
      </div>
    </li>
  )
}

/** What the account holds: each stock with its day line, its value and gain, and a sale of one lot. Pressing a stock opens its page. */
export function Holdings({ account, onRefresh, onSell }: { account: AccountOverview; onRefresh: () => void; onSell: (position: Position, lot: Lot) => void }) {
  const [sort, setSort] = useState<HoldingsSort>("value")
  const held = sortHoldings(heldPositions(account), sort)
  const prices = useLivePrices(account.account_id, held.map((p) => p.symbol))
  const bars = useBars(account.account_id, held.map((p) => p.symbol))
  return (
    <section className={styles.panel} aria-labelledby="holdings-title">
      <header className={styles.panelHead}>
        <div>
          <h2 id="holdings-title" className={styles.panelTitle}>
            Holdings
          </h2>
          <p className={styles.panelMeta}>{held.length === 1 ? "1 stock held" : `${held.length} stocks held`}</p>
        </div>
        {held.length > 1 && <SegmentedControl label="Sort holdings" value={sort} onValueChange={(value) => setSort(value as HoldingsSort)} options={HOLDINGS_SORTS} />}
      </header>
      {held.length === 0 ? (
        <EmptyState
          title="No stocks bought yet"
          description="Shares CopyTrading buys show up here."
          action={
            <Button type="button" variant="secondary" size="sm" onClick={onRefresh}>
              Refresh
            </Button>
          }
        />
      ) : (
        <ul className={styles.holdings}>
          {held.map((position) => (
            <Row key={position.symbol} accountId={account.account_id} position={position} livePrice={prices[position.symbol] ?? null} bars={bars[position.symbol]} onSell={onSell} />
          ))}
        </ul>
      )}
    </section>
  )
}
