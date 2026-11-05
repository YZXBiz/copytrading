// dashboard-8's Release Room panel (a Frame with a progress meter, one outline button and a divided list), wired to
// the account: the loss and invested meters against the limits, Edit Limits, and a row per holding.
import { AnimatePresence, motion } from "motion/react"
import { ArrowDown02Icon } from "@/components/icons/ArrowDown02Icon"
import { ArrowUp02Icon } from "@/components/icons/ArrowUp02Icon"
import { DashboardSpeed01Icon } from "@/components/icons/DashboardSpeed01Icon"
import { MoreHorizontalIcon } from "@/components/icons/MoreHorizontalIcon"
import { PackageOpenIcon } from "@/components/icons/PackageOpenIcon"
import { ShieldCheckIcon } from "@/components/icons/ShieldCheckIcon"
import type { AccountLimits, AccountOverview, Bar } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { EmptyState } from "@/components/empty-state"
import { Frame, FrameDescription, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { RegionError } from "@/components/region-error"
import { RollingNumber } from "@/components/rolling-number"
import { SymbolLogo } from "@/components/symbol-logo"
import { Button } from "@/components/ui/button"
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import { Skeleton } from "@/components/ui/skeleton"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { TickFlash } from "@/features/live/TickFlash"
import { TICK_MS, liveRow } from "@/features/live/live"
import { useLivePrices } from "@/features/live/use-live-prices"
import { money, monthDay, shares, signedPercent } from "@/lib/format"
import { SPRING } from "@/lib/motion"
import { sharesText } from "@/lib/quantity"
import { type Loaded } from "@/lib/use-result"
import { USD_OPTIONS } from "./balance-panel/format"
import { parseDec } from "./decimal"
import { heldPositions } from "./model"
import { PositionSparkline } from "./PositionSparkline"
import { useBars } from "./use-bars"

type Position = AccountOverview["positions"][number]
type Lot = Position["lots"][number]

/** Lots with shares left to sell. */
export const sellable = (position: Position) => position.lots.filter((lot) => (parseDec(lot.remaining_qty) ?? 0n) > 0n)

/** "赵哥, Oct 22, 2.052 shares": which buy a lot is. */
const lotLabel = (position: Position, lot: Lot) =>
  [lot.guru_id ?? "A post", lot.posted_at && monthDay(lot.posted_at), sharesText(parseDec(lot.remaining_qty) ?? 0n, position.symbol)].filter(Boolean).join(", ")

/** The block's buffer meter: its label and share, the bar, and what is used against its limit. */
function Meter({ label, used, cap, usedText, capText }: { label: string; used: number; cap: number; usedText: string; capText: string }) {
  const percent = cap > 0 ? Math.min(100, Math.round((used / cap) * 100)) : 0
  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center justify-between gap-3 text-xs">
        <span className="text-muted-foreground">{label}</span>
        <span className="font-medium tabular-nums">{percent}%</span>
      </div>
      <div className="bg-muted h-2 overflow-hidden rounded-full" role="progressbar" aria-label={label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={percent}>
        <div className="bg-primary h-full rounded-full" style={{ width: `${percent}%` }} />
      </div>
      <div className="text-muted-foreground flex items-center justify-between gap-3 text-xs tabular-nums">
        <span>{usedText}</span>
        <span>{capText}</span>
      </div>
    </div>
  )
}

/** Sell one lot of the stock: the row's menu lists the buys it is made of, so a sale always names the buy it sells. */
function SellMenu({ position, onSell }: { position: Position; onSell: (position: Position, lot: Lot) => void }) {
  const lots = sellable(position)
  if (lots.length === 0) return <span aria-hidden className="size-7 shrink-0" />
  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <Button
            type="button"
            variant="ghost"
            size="icon-sm"
            aria-label={`Sell ${position.symbol}`}
            className="shrink-0 opacity-0 transition-opacity group-focus-within/row:opacity-100 group-hover/row:opacity-100 aria-expanded:opacity-100"
          />
        }
      >
        <MoreHorizontalIcon aria-hidden="true" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-auto">
        {lots.map((lot) => (
          <DropdownMenuItem key={lot.lot_id} onClick={() => onSell(position, lot)}>
            {`Sell ${lotLabel(position, lot)}`}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function Gain({ gain, fraction }: { gain: number | null; fraction: number | null }) {
  const down = (gain ?? 0) < 0
  return (
    <Badge variant={down ? "destructive-light" : "success-light"}>
      {down ? <ArrowDown02Icon aria-hidden="true" /> : <ArrowUp02Icon aria-hidden="true" />}
      {signedPercent(fraction)}
    </Badge>
  )
}

/** The value, rolling to a new figure; with a live price behind it, hovering says so. */
function Value({ value, live }: { value: number | null; live: boolean }) {
  const figure = <RollingNumber value={value} format={USD_OPTIONS} className="text-sm font-medium" />
  if (!live) return figure
  return (
    <Tooltip>
      <TooltipTrigger render={<span className="cursor-default" />}>{figure}</TooltipTrigger>
      <TooltipContent>{`The price shown is live, read every ${TICK_MS / 1000} seconds`}</TooltipContent>
    </Tooltip>
  )
}

function HoldingRow({ position, livePrice, bars, onSell }: { position: Position; livePrice: number | null; bars: Bar[] | undefined; onSell: (position: Position, lot: Lot) => void }) {
  const row = liveRow(position, livePrice)
  return (
    // A new row fades in and the rows around it glide on the shared spring; the first paint animates nothing.
    <motion.li layout="position" transition={SPRING} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="group/row relative">
      <TickFlash price={livePrice} />
      <div className="relative flex items-center gap-3 py-3">
        <SymbolLogo symbol={position.symbol} size="lg" />
        <div className="min-w-0 flex-1">
          <div className="truncate text-sm font-medium">{position.symbol}</div>
          <div className="text-muted-foreground truncate text-xs tabular-nums">{`${shares(position.owned_qty)} shares`}</div>
        </div>
        <PositionSparkline symbol={position.symbol} bars={bars} />
        <div className="flex shrink-0 flex-col items-end gap-1 text-right tabular-nums">
          <Value value={row.value} live={livePrice !== null} />
          <Gain gain={row.gain} fraction={row.gainFraction} />
        </div>
        <SellMenu position={position} onSell={onSell} />
      </div>
    </motion.li>
  )
}

export function LimitsHoldings({
  account,
  limits,
  onRefresh,
  onOpenConnections,
  onEditLimits,
  onSell,
}: {
  account: AccountOverview
  limits: Loaded<AccountLimits | null> & { retry: () => void }
  onRefresh: () => void
  onOpenConnections: () => void
  onEditLimits: () => void
  onSell: (position: Position, lot: Lot) => void
}) {
  const held = heldPositions(account).sort((a, b) => Number(b.market_value ?? 0) - Number(a.market_value ?? 0))
  const prices = useLivePrices(account.account_id, held.map((p) => p.symbol))
  const bars = useBars(account.account_id, held.map((p) => p.symbol))
  const lossToday = Math.max(0, -Number(account.balance?.day_change_usd ?? 0))
  const set = limits.status === "ready" ? limits.data : null
  return (
    <Frame className="h-full min-w-0">
      <FrameHeader className="flex-row items-center justify-between gap-3">
        <div className="flex flex-col gap-px">
          <FrameTitle>Limits and holdings</FrameTitle>
          <FrameDescription>{held.length === 1 ? "1 stock held" : `${held.length} stocks held`}</FrameDescription>
        </div>
      </FrameHeader>

      <FramePanel className="@container flex flex-1 flex-col gap-5">
        {limits.status === "loading" && (
          <div role="status" aria-label="Loading limits" className="flex flex-col gap-4">
            <Skeleton className="h-12 w-full" />
            <Skeleton className="h-12 w-full" />
            <Skeleton className="h-8 w-full" />
          </div>
        )}
        {limits.status === "error" && <RegionError title="Limits did not load" message={limits.error} onRetry={limits.retry} />}
        {limits.status === "ready" && !set && (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <DashboardSpeed01Icon />
              </EmptyMedia>
              <EmptyTitle>No limits to show</EmptyTitle>
              <EmptyDescription>Save the account in Connections first.</EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Button type="button" size="sm" variant="outline" onClick={onOpenConnections}>
                Open Connections
              </Button>
            </EmptyContent>
          </Empty>
        )}
        {set && (
          <div className="flex flex-col gap-4">
            <Meter label="Loss today" used={lossToday} cap={set.daily_loss_cap_usd} usedText={`${money(lossToday)} lost`} capText={`${money(set.daily_loss_cap_usd)} limit`} />
            <Meter
              label="Invested"
              used={Number(account.total_exposure_usd ?? 0)}
              cap={set.max_total_usd}
              usedText={`${money(account.total_exposure_usd ?? 0)} invested`}
              capText={`${money(set.max_total_usd)} total`}
            />
            <dl className="grid grid-cols-3 gap-2 text-xs">
              {[
                ["Each order", money(set.max_order_usd)],
                ["Each stock", money(set.max_symbol_usd)],
                ["Buys per day", String(set.max_entries_per_day)],
              ].map(([label, value]) => (
                <div key={label} className="flex min-w-0 flex-col gap-0.5">
                  <dt className="text-muted-foreground truncate">{label}</dt>
                  <dd className="text-sm font-medium tabular-nums">{value}</dd>
                </div>
              ))}
            </dl>
            <Button type="button" variant="outline" size="sm" className="w-full" onClick={onEditLimits}>
              <ShieldCheckIcon className="size-4" aria-hidden="true" />
              Edit Limits
            </Button>
          </div>
        )}

        <div className="border-border border-t">
          {held.length === 0 ? (
            <EmptyState icon={PackageOpenIcon} title="No stocks bought yet" description="Shares CopyTrading buys show up here." action={{ label: "Refresh", onClick: onRefresh }} />
          ) : (
            <ul className="divide-border flex max-h-72 flex-col divide-y overflow-y-auto">
              <AnimatePresence initial={false}>
                {held.map((position) => (
                  <HoldingRow key={position.symbol} position={position} livePrice={prices[position.symbol] ?? null} bars={bars[position.symbol]} onSell={onSell} />
                ))}
              </AnimatePresence>
            </ul>
          )}
        </div>
      </FramePanel>
    </Frame>
  )
}
