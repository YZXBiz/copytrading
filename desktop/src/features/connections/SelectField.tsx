import type { ReactNode } from "react"
import { Select } from "@/components/arc/select/select"
import styles from "./connections.module.css"

export interface Choice {
  value: string
  label: string
}

/** One pick from a list. */
export function SelectField({ label, hint, value, choices, onChange, placeholder, disabled }: { label: string; hint?: ReactNode; value: string; choices: Choice[]; onChange: (value: string) => void; placeholder?: string; disabled?: boolean }) {
  return (
    <div className={styles.field}>
      <Select label={label} value={value} options={choices} placeholder={placeholder} onValueChange={(next) => next && onChange(next)} disabled={disabled} />
      {hint && <p className={styles.fieldHint}>{hint}</p>}
    </div>
  )
}
