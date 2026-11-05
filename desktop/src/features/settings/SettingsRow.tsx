import type { ReactNode } from "react"
import { Meta } from "@/components/meta"
import styles from "./settings.module.css"

/** One row of a settings section: what it is, a line on it only when it adds a fact, and its control or value on the right. */
export function SettingsRow({
  title,
  description,
  tone,
  stacked,
  children,
}: {
  title: ReactNode
  description?: ReactNode
  /** A caution reads in the row's own colour, so a problem stands out in a list. */
  tone?: "caution"
  /** A control too wide to sit beside the text goes under it. */
  stacked?: boolean
  children?: ReactNode
}) {
  return (
    <div className={styles.row} data-stacked={stacked || undefined}>
      <div className={styles.rowText}>
        <div className={styles.rowTitle}>{title}</div>
        {description && (
          <div className={styles.rowDescription} data-tone={tone}>
            {typeof description === "string" ? <Meta text={description} /> : description}
          </div>
        )}
      </div>
      {children && <div className={styles.rowControl}>{children}</div>}
    </div>
  )
}
