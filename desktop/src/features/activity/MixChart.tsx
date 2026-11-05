import { useMemo } from "react"
import { AnimatedCounter } from "@/components/arc/animated-counter/animated-counter"
import { DonutChart, type DonutChartDatum } from "@/components/arc/donut-chart/donut-chart"
import { OUTCOME_COLOR } from "./chart-config"
import { BUCKETS, BUCKET_LABEL, type GuruMix } from "./post-bucket"
import styles from "./activity.module.css"

export type Mix = { kind: "gurus"; rows: GuruMix[] } | { kind: "reasons"; rows: { reason: string; count: number }[] }

const posts = (n: number) => `${n} ${n === 1 ? "post" : "posts"}`

/** How the month's posts ended and, for two or more gurus, each guru's share; with one guru, the top reasons posts were skipped. */
export function MixChart({ mix }: { mix: Mix }) {
  const gurus = mix.kind === "gurus"
  const data = useMemo<DonutChartDatum[]>(
    () =>
      mix.kind === "gurus"
        ? BUCKETS.map((bucket) => ({ key: bucket, label: BUCKET_LABEL[bucket], value: mix.rows.reduce((n, row) => n + row[bucket], 0), color: OUTCOME_COLOR[bucket] })).filter((d) => d.value > 0)
        : mix.rows.map((row) => ({ key: row.reason, label: row.reason, value: row.count })),
    [mix],
  )
  const total = data.reduce((n, d) => n + d.value, 0)
  return (
    <section className={styles.panel} aria-labelledby="outcome-mix">
      <div className={styles.panelHead}>
        <h2 id="outcome-mix">{gurus ? "Outcome mix" : "Why posts were skipped"}</h2>
        <p>{gurus ? "How posts ended, last 30 days" : "Top reasons, last 30 days"}</p>
      </div>
      {total === 0 ? (
        <p className={styles.quiet}>{gurus ? "No posts in the last 30 days." : "No post was skipped in the last 30 days."}</p>
      ) : (
        <>
          <DonutChart data={data} label={gurus ? "Outcome of posts" : "Reasons posts were skipped"} unit="posts" totalLabel={gurus ? "Total" : "Skipped"} size={192} />
          {mix.kind === "gurus" && (
            <ul className={styles.split} aria-label="Posts by guru">
              {mix.rows.map((row) => (
                <li key={row.guru}>
                  <span>{row.guru}</span>
                  <span>
                    {posts(row.total)}, <AnimatedCounter value={Math.round((row.traded / row.total) * 100)} suffix="%" /> traded
                  </span>
                </li>
              ))}
            </ul>
          )}
        </>
      )}
    </section>
  )
}
