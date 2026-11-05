import type { ComponentProps } from "react"
import { Input } from "@/components/arc/input/input"

/** A labelled input with its one-line hint; an error replaces the hint. Secrets use `type="password"` and are never shown back. */
export function TextField({
  label,
  hint,
  error,
  value,
  onChange,
  ...input
}: {
  label: string
  hint?: string
  error?: string | null
  value: string
  onChange: (value: string) => void
} & Omit<ComponentProps<typeof Input>, "value" | "onChange" | "label" | "description" | "error">) {
  return <Input label={label} description={hint} error={error ?? undefined} value={value} onChange={(event) => onChange(event.target.value)} autoComplete="off" spellCheck={false} {...input} />
}
