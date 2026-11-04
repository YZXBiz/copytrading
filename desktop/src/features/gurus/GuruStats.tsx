// ReUI's Support Metrics (stats-12), installed as shipped: a Frame per figure with its icon tile, the figure, its label and a badge.
import type { ReactNode } from "react"
import { ArrowDownIcon, ArrowUpIcon, MessageSquareIcon, TimerIcon, WalletIcon } from "lucide-react"
import { Badge } from "@/components/reui/badge"
import { Frame, FramePanel } from "@/components/reui/frame"
import { RollingNumber } from "@/components/rolling-number"
import { Item, ItemMedia } from "@/components/ui/item"
import { USD_WHOLE_OPTIONS } from "@/features/account/balance-panel/format"
import { duration } from "@/features/activity/amounts"
import { money } from "@/lib/format"
import { cn } from "@/lib/utils"
import type { Holdings, Stats } from "./model"

const COUNT = { maximumFractionDigits: 0 } as const

interface CardData {
  icon: ReactNode
  iconBg: string
  value: ReactNode
  label: string
  info?: ReactNode
}

/**
 * Today's numbers for one guru, as the engine counted the owner's whole day, and what is held from their calls. Before the
 * day is read every count is a dash, never a zero it has not counted. Nothing shows for holdings while nothing is held.
 */
export function GuruStats({ stats, holdings }: { stats: Stats; holdings: Holdings | null }) {
  const read = stats.postsToday !== null
  const cards: CardData[] = [
    {
      icon: <MessageSquareIcon aria-hidden="true" />,
      iconBg: "text-blue-600 dark:text-blue-400",
      value: <RollingNumber value={stats.postsToday} format={COUNT} />,
      label: "Posts today",
      info: read && (
        <div className="flex flex-wrap gap-1.5">
          <Badge variant="success-light">{(stats.tradedToday ?? 0).toLocaleString("en-US")} traded</Badge>
          <Badge variant={stats.waiting > 0 ? "warning-light" : "outline"}>{stats.waiting.toLocaleString("en-US")} waiting</Badge>
        </div>
      ),
    },
    {
      icon: <TimerIcon aria-hidden="true" />,
      iconBg: "text-emerald-600 dark:text-emerald-400",
      value: stats.averageRead === null ? "—" : duration(stats.averageRead),
      label: "Read in",
    },
  ]
  if (holdings) {
    const up = holdings.gain >= 0
    cards.push({
      icon: <WalletIcon aria-hidden="true" />,
      iconBg: "text-amber-600 dark:text-amber-400",
      value: <RollingNumber value={Math.round(holdings.cost)} format={USD_WHOLE_OPTIONS} />,
      label: `Held in ${holdings.stocks === 1 ? "1 stock" : `${holdings.stocks} stocks`}`,
      info: holdings.cost > 0 && (
        <Badge variant={up ? "success-light" : "destructive-light"}>
          {up ? <ArrowUpIcon aria-hidden="true" /> : <ArrowDownIcon aria-hidden="true" />}
          {money(Math.abs(holdings.gain))} ({Math.abs((holdings.gain / holdings.cost) * 100).toFixed(1)}%)
        </Badge>
      ),
    })
  }
  return (
    <div className="@container w-full grow">
      {/* Grid */}
      <div className="grid grow grid-cols-1 gap-5 @xl:grid-cols-3">
        {cards.map((card) => (
          <Frame key={card.label}>
            <FramePanel className="flex flex-col items-start gap-6">
              <Item
                className={cn(
                  "border-background bg-muted flex size-10.5 items-center justify-center border-2 p-0 shadow-[0_1px_3px_0_rgba(0,0,0,0.14)] dark:border [&_svg]:size-5",
                  card.iconBg
                )}
              >
                <ItemMedia variant="icon" className="size-auto">
                  {card.icon}
                </ItemMedia>
              </Item>

              <div className="space-y-0.5">
                {/* Fixed height: a rolling figure is taller than plain text, and the three cards must line up. */}
                <div className="text-foreground flex h-6 items-center text-2xl leading-none font-bold tabular-nums">{card.value}</div>
                <div className="text-muted-foreground text-sm font-medium">{card.label}</div>
              </div>

              {card.info}
            </FramePanel>
          </Frame>
        ))}
      </div>
    </div>
  )
}
