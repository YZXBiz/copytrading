import { Skeleton } from "@/components/arc/skeleton/skeleton"
import styles from "./account.module.css"

/** The account page's layout with every number still to come: header, balance, figures, limits beside holdings, posts. */
export function AccountPageSkeleton() {
  return (
    <div className={styles.page} aria-busy="true">
      <Skeleton label="Loading account" lines={2} className={styles.skeletonHeader} />
      <Skeleton label="Loading balance" lines={5} className={styles.balance} />
      <div className={styles.figures}>
        {Array.from({ length: 4 }, (_, i) => (
          <Skeleton key={i} label="Loading figure" lines={2} className={styles.figure} />
        ))}
      </div>
      <div className={styles.split}>
        <Skeleton label="Loading limits" lines={5} className={styles.panel} />
        <Skeleton label="Loading holdings" lines={5} className={styles.panel} />
      </div>
      <Skeleton label="Loading posts" lines={5} className={styles.panel} />
    </div>
  )
}
