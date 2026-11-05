import { type ReactNode, useId } from "react"
import { Skeleton } from "@/components/arc/skeleton/skeleton"
import styles from "./settings.module.css"

/** A titled group of settings: a heading, an optional line on what it is for, and its rows divided by hairlines. */
export function SettingsSection({ title, hint, children }: { title?: string; hint?: string; children: ReactNode }) {
  const id = useId()
  return (
    <section className={styles.group} aria-labelledby={title ? id : undefined}>
      {title && <h3 id={id}>{title}</h3>}
      {hint && <p className={styles.hint}>{hint}</p>}
      <div className={styles.rows}>{children}</div>
    </section>
  )
}

/** A section's rows while they load, in the shape they will have. */
export function SectionSkeleton({ rows = 1, label = "Loading" }: { rows?: number; label?: string }) {
  return <Skeleton label={label} lines={rows} />
}
