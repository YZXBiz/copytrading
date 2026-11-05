import { Alert } from "@/components/arc/alert/alert"
import { Button } from "@/components/arc/button/button"
import styles from "./activity.module.css"

/** The inline error of a data region: what failed, in the engine's words, and a Retry. */
export function RegionAlert({ title, message, onRetry }: { title: string; message: string; onRetry: () => void }) {
  return (
    <Alert tone="danger" title={title}>
      <span className={styles.alertText}>{message}</span>
      <Button variant="secondary" size="sm" onClick={onRetry}>
        Retry
      </Button>
    </Alert>
  )
}
