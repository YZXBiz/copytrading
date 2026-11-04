import type { ReactNode } from "react"

/** A quiet figure: its label in muted text, then its value, and a note only when the value alone would mislead. Put several in a `dl`. */
export function Figure({ label, value, note }: { label: string; value: ReactNode; note?: string }) {
  return (
    <div className="flex items-baseline gap-1.5 text-sm">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="tabular-nums">
        {value}
        {note && <span className="text-muted-foreground ms-1.5 text-xs">{note}</span>}
      </dd>
    </div>
  )
}
