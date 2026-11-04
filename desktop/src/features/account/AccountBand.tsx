import type { ReactNode } from "react"
import { BanknoteIcon, BellIcon, ChartNoAxesColumnIcon, ShieldCheckIcon, WalletIcon } from "lucide-react"
import type { AccountOverview } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Frame, FramePanel } from "@/components/reui/frame"
import { RollingNumber } from "@/components/rolling-number"
import { Button } from "@/components/ui/button"
import { Item, ItemActions, ItemContent, ItemDescription, ItemMedia, ItemTitle } from "@/components/ui/item"
import { percent } from "@/lib/format"
import { getTimeZone } from "@/lib/time-zone"
import { cn } from "@/lib/utils"
import { type AccountControl, ControlButton } from "./AccountControl"
import { USD_OPTIONS, USD_SIGNED_OPTIONS } from "./balance-panel/format"
import { COPYING_TITLE, badgeVariant, isWarning } from "./copying"
import { dayChange } from "./model"

const today = (now: Date) => new Intl.DateTimeFormat("en-US", { timeZone: getTimeZone(), weekday: "long", month: "short", day: "numeric", year: "numeric" }).format(now)

/** One of dashboard-8's summary tiles: an icon, the label over its detail, and the figure. Given `onClick` it is a button. */
function SummaryTile({ icon, label, detail, value, onClick }: { icon: ReactNode; label: string; detail: string; value: ReactNode; onClick?: () => void }) {
  return (
    <Item variant="outline" size="sm" className={cn("min-w-0 flex-nowrap items-center gap-2.5", onClick && "hover:bg-muted/50 cursor-pointer text-left transition-colors")} render={onClick ? <button type="button" onClick={onClick} /> : undefined}>
      <ItemMedia variant="icon" className="text-muted-foreground size-auto [&_svg]:size-4">
        {icon}
      </ItemMedia>
      <ItemContent className="min-w-0 gap-0.5">
        <ItemTitle className="text-muted-foreground w-full truncate text-xs font-medium">{label}</ItemTitle>
        <ItemDescription className="truncate text-xs">{detail}</ItemDescription>
      </ItemContent>
      <ItemActions className="ml-auto shrink-0 flex-col items-end gap-1">
        <span className="text-sm leading-none font-semibold tabular-nums">{value}</span>
      </ItemActions>
    </Item>
  )
}

/**
 * ReUI's dashboard-8 command band: the account's badges and date, its name and what it copies, the balance with
 * today's change and the two buttons, and four tiles under them.
 */
export function AccountBand({
  account,
  guru,
  now,
  waiting,
  control,
  canEditLimits,
  onEditLimits,
  onShowWaiting,
}: {
  account: AccountOverview
  /** The guru this account copies, once the limits have loaded. */
  guru: string | null
  now: Date
  waiting: number
  control: AccountControl
  canEditLimits: boolean
  onEditLimits: () => void
  onShowWaiting: () => void
}) {
  const { state } = control
  const balance = account.balance
  const equity = Number(balance?.equity)
  const share = (part: string | null | undefined) => (equity > 0 && part != null ? `${percent(Number(part) / equity, 0)} of equity` : "In the account")
  const change = dayChange(account)
  const subtitle = state.detail ?? (guru ? `Copies ${guru}` : null)
  return (
    <Frame>
      <FramePanel className="flex flex-col gap-4">
        <div className="flex min-w-0 flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
          <div className="flex min-w-0 flex-col gap-3">
            <div className="flex flex-wrap items-center gap-2">
              <Badge variant="primary-light">{account.environment === "paper" ? "Paper" : "Live"}</Badge>
              <Badge variant={badgeVariant(state)}>{COPYING_TITLE[state.word]}</Badge>
              <span className="text-muted-foreground text-xs tabular-nums">{today(now)}</span>
            </div>
            <div className="flex min-w-0 flex-col gap-1">
              <h1 className="truncate text-2xl font-semibold tracking-tight">{account.account_id}</h1>
              {subtitle && <p className={cn("text-sm", state.detail && isWarning(state) ? "text-foreground" : "text-muted-foreground")}>{subtitle}</p>}
            </div>
          </div>

          <div className="border-border flex min-w-0 flex-col gap-3 border-t pt-4 sm:flex-row sm:items-end sm:justify-between lg:w-[360px] lg:border-t-0 lg:pt-0">
            <div className="min-w-0 lg:text-right">
              <div className="text-muted-foreground text-sm">Balance</div>
              <div className="mt-1 text-3xl font-semibold tracking-tight tabular-nums">
                <RollingNumber value={balance ? equity : null} format={USD_OPTIONS} />
              </div>
              {change && (
                <div className={cn("mt-1 text-sm tabular-nums", change.amount < 0 ? "text-destructive" : change.amount > 0 ? "text-success" : "text-muted-foreground")}>
                  <RollingNumber value={change.amount} format={USD_SIGNED_OPTIONS} /> <span className="text-muted-foreground">today</span>
                </div>
              )}
            </div>

            <div className="grid w-full grid-cols-2 gap-2 sm:w-60 lg:w-full">
              <Button type="button" size="sm" disabled={!canEditLimits} onClick={onEditLimits}>
                <ShieldCheckIcon aria-hidden="true" />
                Edit Limits
              </Button>
              <ControlButton control={control} variant="outline" />
            </div>
          </div>
        </div>

        <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-[1fr_1fr_1.4fr_1fr]">
          <SummaryTile icon={<WalletIcon aria-hidden="true" />} label="Cash" detail={share(balance?.cash)} value={<RollingNumber value={Number(balance?.cash)} format={USD_OPTIONS} />} />
          <SummaryTile icon={<BanknoteIcon aria-hidden="true" />} label="Buying power" detail="to spend" value={<RollingNumber value={Number(balance?.buying_power)} format={USD_OPTIONS} />} />
          <SummaryTile
            icon={<ChartNoAxesColumnIcon aria-hidden="true" />}
            label="Invested by CopyTrading"
            detail={account.pending_orders ? `${account.pending_orders} orders waiting` : share(account.total_exposure_usd)}
            value={<RollingNumber value={Number(account.total_exposure_usd ?? 0)} format={USD_OPTIONS} />}
          />
          <SummaryTile icon={<BellIcon aria-hidden="true" />} label="Waiting for you" detail={waiting === 0 ? "all answered" : "to answer"} value={waiting} onClick={onShowWaiting} />
        </div>
      </FramePanel>
    </Frame>
  )
}
