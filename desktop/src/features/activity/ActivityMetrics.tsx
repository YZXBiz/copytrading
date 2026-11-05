import type { ReactNode } from "react"
import { ArrowLeftRightIcon } from "@/components/icons/ArrowLeftRightIcon"
import { Clock01Icon } from "@/components/icons/Clock01Icon"
import { Message01Icon } from "@/components/icons/Message01Icon"
import { SkipForwardIcon } from "@/components/icons/SkipForwardIcon"
import { TrendingDownIcon } from "@/components/icons/TrendingDownIcon"
import { TrendingUpIcon } from "@/components/icons/TrendingUpIcon"
import { Badge, type BadgeProps } from "@/components/reui/badge"
import { Frame, FramePanel } from "@/components/reui/frame"
import { KpiSparkline } from "@/components/kpi-sparkline"
import { RollingNumber } from "@/components/rolling-number"
import { Item, ItemMedia } from "@/components/ui/item"
import { type DayCounts, type Metric } from "./post-bucket"

const CARDS: { id: Metric; title: string; detail: string; icon: ReactNode; badge: BadgeProps["variant"]; line: string }[] = [
  { id: "posts", title: "Posts", detail: "From your gurus", icon: <Message01Icon />, badge: "info-light", line: "text-info" },
  { id: "traded", title: "Traded", detail: "Orders placed", icon: <ArrowLeftRightIcon />, badge: "primary-light", line: "text-primary" },
  { id: "waiting", title: "Waiting", detail: "Need your call", icon: <Clock01Icon />, badge: "warning-light", line: "text-warning" },
  { id: "skipped", title: "Skipped", detail: "Not copied", icon: <SkipForwardIcon />, badge: "outline", line: "text-muted-foreground" },
]

const WHOLE = { maximumFractionDigits: 0 }

/** dashboard-7's raised icon tile, as shipped. */
function IconContainer({ icon }: { icon: ReactNode }) {
  return (
    <Item className="border-background bg-muted [&_svg]:text-accent-foreground flex size-9 shrink-0 items-center justify-center border-2 p-0 shadow-[0_1px_3px_0_rgba(0,0,0,0.14)] dark:border [&_svg]:size-4">
      <ItemMedia variant="icon" className="size-auto">
        {icon}
      </ItemMedia>
    </Item>
  )
}

const signed = (n: number) => (n > 0 ? `+${n}` : n < 0 ? `−${Math.abs(n)}` : "0")

/** dashboard-7's four KPI panels: the day's count, its change from the day before, and the count for each hour. */
export function ActivityMetrics({ today, before }: { today: DayCounts; before: DayCounts }) {
  return (
    <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4 xl:gap-3">
      {CARDS.map((card) => {
        const hours = today.hours[card.id]
        const change = today.total[card.id] - before.total[card.id]
        return (
          <Frame key={card.id}>
            <FramePanel className="flex min-h-28 flex-col justify-between gap-3">
              <div className="flex items-start justify-between gap-2">
                <div className="flex min-w-0 items-start gap-3">
                  <IconContainer icon={card.icon} />
                  <div className="min-w-0 pt-0.5">
                    <span className="block truncate text-sm font-medium">{card.title}</span>
                    <span className="text-muted-foreground block truncate text-xs">{card.detail}</span>
                  </div>
                </div>
                <Badge variant={card.badge} aria-label={`${signed(change)} from the day before`}>
                  {change < 0 ? <TrendingDownIcon className="size-3" aria-hidden="true" /> : <TrendingUpIcon className="size-3" aria-hidden="true" />}
                  {signed(change)}
                </Badge>
              </div>
              <div className="grid grid-cols-[1fr_auto] items-end gap-2">
                <div className="min-w-0">
                  <div className="text-xl font-semibold tracking-tight tabular-nums">
                    <RollingNumber value={today.total[card.id]} format={WHOLE} />
                  </div>
                </div>
                {/* The count for each hour of the day, as one line. */}
                <KpiSparkline values={hours} className={card.line} />
              </div>
            </FramePanel>
          </Frame>
        )
      })}
    </div>
  )
}
