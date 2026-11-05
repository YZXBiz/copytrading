import { useId } from "react"
import SegmentedControl from "@/components/arc/segmented-control/segmented-control"
import styles from "./connections.module.css"

/** A choice between a few words, one always picked. */
export function ChoiceField<T extends string>({ label, hint, value, choices, onChange, disabled }: { label: string; hint?: string; value: T; choices: { value: T; label: string }[]; onChange: (value: T) => void; disabled?: boolean }) {
  const id = useId()
  return (
    <div className={styles.field} aria-disabled={disabled || undefined}>
      <span id={id} className={styles.fieldLabel}>
        {label}
      </span>
      <SegmentedControl label={label} options={choices} value={value} onValueChange={(next) => !disabled && onChange(next as T)} />
      {hint && <p className={styles.fieldHint}>{hint}</p>}
    </div>
  )
}
