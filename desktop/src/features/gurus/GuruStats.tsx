import { ArrowDownIcon, ArrowUpIcon } from "lucide-react"
import { Figure } from "@/components/figure"
import { Badge } from "@/components/reui/badge"
import { duration } from "@/features/activity/amounts"
import { money } from "@/lib/format"
import { dollars } from "@/lib/quantity"
import type { Holdings, Stats } from "./model"

/**
 * Today's numbers for one guru, as the engine counted the owner's whole day, and what is held from their calls, in one quiet
 * row. Before the day is read every count is a dash, never a zero it has not counted. Waiting is the only count that carries a tone.
 */
export function GuruStats({ stats, holdings }: { stats: Stats; holdings: Holdings | null }) {
  const count = (n: number | null) => (n === null ? "—" : n.toLocaleString("en-US"))
  const waiting = stats.postsToday === null ? "—" : stats.waiting > 0 ? <Badge variant="warning-light">{stats.waiting}</Badge> : "0"
  return (
    <dl aria-label="Today" className="flex flex-wrap gap-x-8 gap-y-2">
      <Figure label="Posts today" value={count(stats.postsToday)} />
      <Figure label="Traded" value={count(stats.tradedToday)} />
      <Figure label="Waiting" value={waiting} />
      <Figure label="Read in" value={stats.averageRead === null ? "—" : duration(stats.averageRead)} />
      {holdings && <Holding holdings={holdings} />}
    </dl>
  )
}

/** What the owner holds from this guru's calls right now, then how that stands today. Nothing shows while nothing is held. */
function Holding({ holdings: { cost, gain, stocks } }: { holdings: Holdings }) {
  const up = gain >= 0
  return (
    <Figure
      label="Holding"
      value={
        <span className="inline-flex items-baseline gap-1.5">
          {dollars(String(Math.round(cost)))} in {stocks === 1 ? "1 stock" : `${stocks} stocks`}
          {cost > 0 && (
            <Badge variant={up ? "success-light" : "destructive-light"}>
              {up ? <ArrowUpIcon aria-hidden="true" /> : <ArrowDownIcon aria-hidden="true" />}
              {money(Math.abs(gain))} ({Math.abs((gain / cost) * 100).toFixed(1)}%)
            </Badge>
          )}
        </span>
      }
    />
  )
}
