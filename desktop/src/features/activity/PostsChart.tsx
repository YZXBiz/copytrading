import { useMemo } from "react"
import { AnimatedCounter } from "@/components/arc/animated-counter/animated-counter"
import { LineChart, type LineChartDatum } from "@/components/arc/line-chart/line-chart"
import { OUTCOME_SERIES } from "./chart-config"
import { BUCKETS, type DayRow } from "./post-bucket"
import styles from "./activity.module.css"

const sum = (rows: DayRow[], ...keys: (typeof BUCKETS)[number][]) => rows.reduce((n, row) => n + keys.reduce((m, key) => m + row[key], 0), 0)
const longDay = (key: string) => new Date(`${key}T12:00:00Z`).toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric", timeZone: "UTC" })

/** Posts per day over the last 30 days, one line for how each ended. */
export function PostsChart({ rows }: { rows: DayRow[] }) {
  const posts = sum(rows, ...BUCKETS)
  const traded = sum(rows, "traded")
  // The same array on every render: the screen re-renders every few seconds and a new one would redraw the lines.
  const data = useMemo<LineChartDatum[]>(
    () => rows.map((row, index) => ({ key: row.key, label: longDay(row.key), axisLabel: index % 4 === 0 ? row.label : undefined, values: { traded: row.traded, waiting: row.waiting, skipped: row.skipped, ignored: row.ignored } })),
    [rows],
  )
  return (
    <section className={styles.panel} aria-labelledby="posts-per-day">
      <div className={styles.panelHead}>
        <h2 id="posts-per-day">Posts per day</h2>
        <p>Last 30 days, by how each ended</p>
      </div>
      <dl className={styles.stats}>
        <div>
          <dt>Posts</dt>
          <dd>
            <AnimatedCounter value={posts} />
          </dd>
        </div>
        <div>
          <dt>Traded</dt>
          <dd>
            <AnimatedCounter value={traded} />
            {posts > 0 && <small>{Math.round((traded / posts) * 100)}%</small>}
          </dd>
        </div>
        <div>
          <dt>Skipped</dt>
          <dd>
            <AnimatedCounter value={sum(rows, "skipped")} />
          </dd>
        </div>
      </dl>
      <LineChart data={data} series={OUTCOME_SERIES} label="Posts per day" unit="posts" height={300} categoryLabel="Day" curve="linear" formatTick={(value) => String(Math.round(value))} />
    </section>
  )
}
