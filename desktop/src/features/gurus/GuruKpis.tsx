// solution-analytics-8's KPI rail (MetricKpis), as shipped: a Frame tile per figure with its value, a badge, a separator and a
// footer line. Changed from the block: the data, and the figures roll.
import type { ReactNode } from "react"
import { ArrowDown02Icon } from "@/components/icons/ArrowDown02Icon"
import { ArrowUp02Icon } from "@/components/icons/ArrowUp02Icon"
import type { GuruPerformance } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Frame, FramePanel } from "@/components/reui/frame"
import { RollingNumber } from "@/components/rolling-number"
import { Separator } from "@/components/ui/separator"
import { USD_OPTIONS, USD_SIGNED_OPTIONS } from "@/features/account/balance-panel/format"
import { monthDay, signedMoney } from "@/lib/format"
import { cn } from "@/lib/utils"
import type { Holdings, Stats } from "./model"

const COUNT = { maximumFractionDigits: 0 } as const
const PERCENT = { style: "percent", maximumFractionDigits: 0 } as const

const tone = (n: number) => (n > 0 ? "text-success" : n < 0 ? "text-destructive" : undefined)
const strong = (text: ReactNode) => <span className="text-foreground font-medium">{text}</span>

interface Tile {
  title: string
  value: ReactNode
  valueClass?: string
  badge?: ReactNode
  footer: ReactNode
}

/**
 * Posts today, win rate, realized profit and what is held. Before a figure is read it is a dash, never a zero that was not
 * counted; nothing held reads as a dash with its footer saying so.
 */
export function GuruKpis({ stats, performance, holdings }: { stats: Stats; performance: GuruPerformance | null; holdings: Holdings | null | undefined }) {
  const realized = performance ? Number(performance.realized_usd) : null
  const closed = performance?.closed_trades ?? 0
  const first = performance?.series[0]
  const held = holdings ? holdings.cost + holdings.gain : holdings === null ? 0 : null
  const up = (holdings?.gain ?? 0) >= 0
  const tiles: Tile[] = [
    {
      title: "Posts today",
      value: <RollingNumber value={stats.postsToday} format={COUNT} />,
      badge: stats.tradedToday !== null && <Badge variant="success-light">{stats.tradedToday.toLocaleString("en-US")} traded</Badge>,
      footer: stats.postsToday === null ? "Reading today's posts" : <>{strong(stats.waiting.toLocaleString("en-US"))} waiting</>,
    },
    {
      title: "Win rate",
      value: <RollingNumber value={performance && closed > 0 ? performance.winning_trades / closed : null} format={PERCENT} />,
      footer: performance ? (closed > 0 ? <>{strong(performance.winning_trades)} of {strong(closed)} closed trades</> : "No closed trades yet") : "Reading trades",
    },
    {
      title: "Realized P&L",
      value: <RollingNumber value={realized} format={USD_SIGNED_OPTIONS} />,
      valueClass: realized === null ? undefined : tone(realized),
      footer: first ? <>since {strong(monthDay(`${first.day}T12:00:00Z`))}</> : performance ? "No sales closed yet" : "Reading trades",
    },
    {
      title: "Holding value",
      value: <RollingNumber value={held} format={USD_OPTIONS} />,
      badge:
        holdings && holdings.cost > 0 ? (
          <Badge variant={up ? "success-light" : "destructive-light"}>
            {up ? <ArrowUp02Icon aria-hidden="true" /> : <ArrowDown02Icon aria-hidden="true" />}
            {Math.abs((holdings.gain / holdings.cost) * 100).toFixed(1)}%
          </Badge>
        ) : null,
      footer: holdings ? <>{strong(signedMoney(holdings.gain))} in {holdings.stocks === 1 ? "1 stock" : `${holdings.stocks} stocks`}</> : holdings === null ? "Nothing held from this guru" : "Reading holdings",
    },
  ]
  return (
    <div className="grid grid-cols-2 gap-4 lg:grid-cols-4 lg:gap-6">
      {tiles.map((tile) => (
        <Frame key={tile.title}>
          <FramePanel className="flex flex-col gap-4">
            <h3 className="text-muted-foreground text-sm font-medium">{tile.title}</h3>
            <div className="space-y-2.5">
              <div className="flex flex-wrap items-center gap-2.5">
                <span className={cn("text-foreground inline-flex h-9 items-center text-2xl font-medium tracking-tight tabular-nums", tile.valueClass)}>{tile.value}</span>
                {tile.badge}
              </div>
              <Separator />
              <div className="text-muted-foreground text-xs">{tile.footer}</div>
            </div>
          </FramePanel>
        </Frame>
      ))}
    </div>
  )
}
