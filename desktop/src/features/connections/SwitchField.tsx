import { useId } from "react"
import { Switch } from "@/components/arc/switch/switch"
import styles from "./connections.module.css"

/** A setting that is on or off, with what it does under its name. */
export function SwitchField({ title, hint, checked, onChange, disabled }: { title: string; hint: string; checked: boolean; onChange: (checked: boolean) => void; disabled?: boolean }) {
  const id = useId()
  return (
    <div className={styles.switchRow}>
      <div>
        <span id={`${id}-title`} className={styles.switchTitle}>
          {title}
        </span>
        <span id={`${id}-hint`} className={styles.fieldHint}>
          {hint}
        </span>
      </div>
      <Switch aria-labelledby={`${id}-title`} aria-describedby={`${id}-hint`} checked={checked} onCheckedChange={onChange} disabled={disabled} />
    </div>
  )
}
