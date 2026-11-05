import { Skeleton } from "@/components/arc/skeleton/skeleton"
import styles from "./activity.module.css"

/** The page's layout with every number still to come: header, four cards, two charts, the posts. */
export function ActivitySkeleton() {
  return (
    <div role="status" aria-busy="true" aria-label="Loading posts" className={styles.page}>
      <Skeleton label="Loading the day" lines={1} />
      <div className={styles.cardsSkeleton}>
        {Array.from({ length: 4 }, (_, i) => (
          <Skeleton key={i} label="Loading a figure" lines={2} className={styles.block} />
        ))}
      </div>
      <div className={styles.charts}>
        <Skeleton label="Loading the chart" lines={5} className={styles.tall} />
        <Skeleton label="Loading the chart" lines={5} className={styles.tall} />
      </div>
      <Skeleton label="Loading posts" lines={6} avatar />
    </div>
  )
}
