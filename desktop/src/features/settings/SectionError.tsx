import { Alert } from "@/components/arc/alert/alert"
import { Button } from "@/components/arc/button/button"

/** The inline error of a data region: what failed, in the engine's words, and a retry. */
export function SectionError({ title, message, onRetry }: { title: string; message: string; onRetry: () => void }) {
  return (
    <Alert tone="danger" title={title}>
      <p style={{ margin: 0 }}>{message}</p>
      <Button type="button" variant="secondary" size="sm" onClick={onRetry} style={{ marginTop: 8 }}>
        Try again
      </Button>
    </Alert>
  )
}
