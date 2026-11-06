import { useMemo } from "react"
import { AnimatedCounter } from "@/components/arc/animated-counter/animated-counter"
import { SankeyFlow } from "@/components/arc/sankey-flow/sankey-flow"
import { type GuruMix, outcomeFlow } from "./post-bucket"
import styles from "./activity.module.css"

const posts = (n: number) => `${n} ${n === 1 ? "post" : "posts"}`

/** How the month's posts ended: every post flows into Traded, Waiting, Skipped or Ignored, with each guru's share under it. */
export function OutcomeFlow({ rows }: { rows: GuruMix[] }) {
  // The same object on every render: the screen re-renders every few seconds and a new one would redraw the flow.
  const { nodes, links } = useMemo(() => outcomeFlow(rows), [rows])
  return (
    <section className={styles.panel} aria-labelledby="outcome-flow">
      <div className={styles.panelHead}>
        <h2 id="outcome-flow">Outcome flow</h2>
        <p>How posts ended, last 30 days</p>
      </div>
      {links.length === 0 ? (
        <p className={styles.quiet}>No posts in the last 30 days.</p>
      ) : (
        <>
          <SankeyFlow nodes={nodes} links={links} label="How posts ended" unit="posts" totalLabel="all posts" height={300} defaultParticles={false} particleToggle={false} />
          <ul className={styles.split} aria-label="Posts by guru">
            {rows.map((row) => (
              <li key={row.guru}>
                <span>{row.guru}</span>
                <span>
                  {posts(row.total)}, <AnimatedCounter value={Math.round((row.traded / row.total) * 100)} suffix="%" /> traded
                </span>
              </li>
            ))}
          </ul>
        </>
      )}
    </section>
  )
}
