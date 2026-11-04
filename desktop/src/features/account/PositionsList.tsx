// ReUI's Crypto Portfolio list (list-4), installed as shipped and wired to the account's positions: the tabbed
// header (here ordering the list), a row per holding with its price and trend badge on the left and its value
// and holdings on the right, now with the Sell action and the columns the old table had.
import { useState } from "react"
import { AnimatePresence, motion } from "motion/react"
import { ArrowDownIcon, ArrowUpIcon, ChevronDownIcon, PackageOpenIcon } from "lucide-react"
import type { AccountOverview } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Frame, FramePanel } from "@/components/reui/frame"
import { RollingNumber } from "@/components/rolling-number"
import { SymbolLogo } from "@/components/symbol-logo"
import { Button } from "@/components/ui/button"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import { EmptyState } from "@/components/empty-state"
import { Separator } from "@/components/ui/separator"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { USD_OPTIONS } from "@/features/account/balance-panel/format"
import { TickFlash } from "@/features/live/TickFlash"
import { TICK_MS, liveRow } from "@/features/live/live"
import { useLivePrices } from "@/features/live/use-live-prices"
import { SPRING } from "@/lib/motion"
import { money, monthDay, shares, signedMoney, signedPercent } from "@/lib/format"
import { sharesText } from "@/lib/quantity"
import { parseDec } from "./decimal"
import { heldPositions, holdingNote } from "./model"
import { SORTS, type SortKey, sortPositions } from "./positions-sort"

type Position = AccountOverview["positions"][number]
type Lot = Position["lots"][number]

/** Lots with shares left to sell. */
export const sellable = (position: Position) => position.lots.filter((lot) => (parseDec(lot.remaining_qty) ?? 0n) > 0n)

/** "赵哥, Oct 22, 2.052 shares": which buy a lot is. */
const lotLabel = (position: Position, lot: Lot) =>
  [lot.guru_id ?? "A post", lot.posted_at && monthDay(lot.posted_at), sharesText(parseDec(lot.remaining_qty) ?? 0n, position.symbol)].filter(Boolean).join(", ")

/** Sell one lot of the stock: one Sell button, or a menu of the lots when several buys make it up. */
function SellCell({ position, onSell }: { position: Position; onSell: (position: Position, lot: Lot) => void }) {
  const lots = sellable(position)
  if (lots.length === 0) return null
  if (lots.length === 1) {
    return (
      <Button type="button" size="sm" variant="outline" aria-label={`Sell ${lotLabel(position, lots[0]!)}`} onClick={() => onSell(position, lots[0]!)}>
        Sell
      </Button>
    )
  }
  return (
    <DropdownMenu>
      <DropdownMenuTrigger render={<Button type="button" size="sm" variant="outline" aria-label={`Sell ${position.symbol}: choose a buy`} />}>
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

function TrendBadge({ gain, fraction }: { gain: number | null; fraction: number | null }) {
  const down = (gain ?? 0) < 0
  return (
    <Badge variant={down ? "destructive-light" : "success-light"}>
      {down ? <ArrowDownIcon aria-hidden="true" /> : <ArrowUpIcon aria-hidden="true" />}
      {signedPercent(fraction)}
    </Badge>
  )
}

/** A figure that rolls to a new value; with a live price behind it, hovering says so. */
function Figure({ value, live, className }: { value: number | null; live: boolean; className: string }) {
  const figure = <RollingNumber value={value} format={USD_OPTIONS} className={className} />
  if (!live) return figure
  return (
    <Tooltip>
      <TooltipTrigger render={<span className="cursor-default" />}>{figure}</TooltipTrigger>
      <TooltipContent>{`The price shown is live, read every ${TICK_MS / 1000} seconds`}</TooltipContent>
    </Tooltip>
  )
}

function PositionRow({ position, livePrice, showSeparator, onSell }: { position: Position; livePrice: number | null; showSeparator: boolean; onSell: (position: Position, lot: Lot) => void }) {
  const note = holdingNote(position)
  const row = liveRow(position, livePrice)
  const isLive = livePrice !== null
  return (
    // A new row fades in and the rows around it glide on the shared spring; the first paint animates nothing.
    <motion.li layout="position" transition={SPRING} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="relative">
      <TickFlash price={livePrice} />
      <div className="relative flex items-center gap-2">
        <SymbolLogo symbol={position.symbol} />
        <div className="flex min-w-0 flex-1 flex-col gap-0">
          <p className="text-foreground text-base leading-5 font-medium">
            {position.symbol}
            {note && <span className="text-muted-foreground ms-2 text-sm font-normal">{note}</span>}
          </p>
          <div className="flex min-w-0 flex-wrap items-center gap-1.5">
            <Figure value={row.price} live={isLive} className="text-muted-foreground text-sm leading-4 tabular-nums" />
            <TrendBadge gain={row.gain} fraction={row.gainFraction} />
            <span className="text-muted-foreground text-sm leading-4 tabular-nums">{signedMoney(row.gain)}</span>
          </div>
        </div>

        <div className="flex shrink-0 flex-col gap-0 text-right">
          <p className="text-foreground text-base leading-5 font-medium tabular-nums">
            <RollingNumber value={row.value} format={USD_OPTIONS} />
          </p>
          <p className="text-muted-foreground text-sm leading-4 tabular-nums">{`${shares(position.owned_qty)} shares at ${money(position.avg_entry_price)}`}</p>
        </div>

        <SellCell position={position} onSell={onSell} />
      </div>
      {showSeparator ? <Separator className="my-3.5 w-auto border-t border-dashed bg-transparent" /> : null}
    </motion.li>
  )
}

export function PositionsList({ account, onRefresh, onSell }: { account: AccountOverview; onRefresh: () => void; onSell: (position: Position, lot: Lot) => void }) {
  const [sort, setSort] = useState<SortKey>("value")
  const rows = sortPositions(heldPositions(account), sort)
  const prices = useLivePrices(account.account_id, rows.map((p) => p.symbol))
  return (
    <Tabs value={sort} onValueChange={(next) => setSort(next as SortKey)} className="w-full">
      <Frame stacked className="@container w-full">
        <FramePanel className="flex items-center justify-between p-3.5!">
          {/* Header */}
          <h2 className="text-foreground text-base font-medium">Positions</h2>
          <TabsList aria-label="Order positions by">
            {SORTS.map((option) => (
              <TabsTrigger key={option.value} value={option.value}>
                {option.label}
              </TabsTrigger>
            ))}
          </TabsList>
        </FramePanel>

        <FramePanel className="px-5! pt-3! pb-4!">
          {/* Content */}
          {rows.length === 0 ? (
            <EmptyState icon={PackageOpenIcon} title="No stocks bought yet" description="Shares CopyTrading buys show up here." action={{ label: "Refresh", onClick: onRefresh }} />
          ) : (
            <ul className="flex flex-col">
              <AnimatePresence initial={false}>
                {rows.map((position, index) => (
                  <PositionRow key={position.symbol} position={position} livePrice={prices[position.symbol] ?? null} showSeparator={index < rows.length - 1} onSell={onSell} />
                ))}
              </AnimatePresence>
            </ul>
          )}
        </FramePanel>
      </Frame>
    </Tabs>
  )
}
