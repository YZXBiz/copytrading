import { useMemo } from "react"
import { DonutChart, type DonutChartDatum } from "@/components/arc/donut-chart/donut-chart"
import type { GuruMix } from "./post-bucket"
import { OutcomeFlow } from "./OutcomeFlow"
import styles from "./activity.module.css"

export type Mix = { kind: "gurus"; rows: GuruMix[] } | { kind: "reasons"; rows: { reason: string; count: number }[] }

/** For two or more gurus, how posts ended and each guru's share; with one guru, the top reasons posts were skipped. */
export function MixChart({ mix }: { mix: Mix }) {
  if (mix.kind === "gurus") return <OutcomeFlow rows={mix.rows} />
  return <SkipReasons rows={mix.rows} />
}

function SkipReasons({ rows }: { rows: { reason: string; count: number }[] }) {
  const data = useMemo<DonutChartDatum[]>(() => rows.map((row) => ({ key: row.reason, label: row.reason, value: row.count })), [rows])
  return (
    <section className={styles.panel} aria-labelledby="outcome-mix">
      <div className={styles.panelHead}>
        <h2 id="outcome-mix">Why posts were skipped</h2>
        <p>Top reasons, last 30 days</p>
      </div>
      {data.length === 0 ? <p className={styles.quiet}>No post was skipped in the last 30 days.</p> : <DonutChart data={data} label="Reasons posts were skipped" unit="posts" totalLabel="Skipped" size={192} />}
    </section>
  )
}
