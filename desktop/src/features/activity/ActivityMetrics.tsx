import { MetricCard } from "@/components/arc/metric-card/metric-card"
import { type DayCounts, type Metric } from "./post-bucket"
import styles from "./activity.module.css"

const CARDS: { id: Metric; label: string }[] = [
  { id: "posts", label: "Posts" },
  { id: "traded", label: "Traded" },
  { id: "waiting", label: "Waiting" },
  { id: "skipped", label: "Skipped" },
]

/** How the count moved from the day before, in words: a count going up is not good or bad news, so it gets no colour. */
const moved = (change: number) => (change === 0 ? "Same as the day before" : `${change > 0 ? "+" : "−"}${Math.abs(change)} from the day before`)

/** Four cards: the day's count of posts, and of those traded, waiting and skipped, each against the day before. */
export function ActivityMetrics({ today, before }: { today: DayCounts; before: DayCounts }) {
  return (
    <div className={styles.kpis}>
      {CARDS.map((card) => (
        <MetricCard key={card.id} label={card.label} value={today.total[card.id]} context={moved(today.total[card.id] - before.total[card.id])} />
      ))}
    </div>
  )
}
