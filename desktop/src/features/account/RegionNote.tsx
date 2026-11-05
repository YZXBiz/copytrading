import { Alert } from "@/components/arc/alert/alert"
import { Button } from "@/components/arc/button/button"
import styles from "./account.module.css"

/** The inline error of a data region: what failed, in the engine's words, and a Retry. */
export function RegionNote({ title, message, onRetry }: { title: string; message: string; onRetry: () => void }) {
  return (
    <Alert tone="danger" title={title}>
      <p className={styles.alertText}>{message}</p>
      <Button type="button" size="sm" variant="secondary" onClick={onRetry}>
        Retry
      </Button>
    </Alert>
  )
}
