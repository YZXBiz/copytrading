import { useId, type ComponentProps } from "react"
import { Field, FieldDescription, FieldError, FieldLabel } from "@/components/ui/field"
import { Input } from "@/components/ui/input"

/** A labelled input with its one-line hint, and an error that replaces the hint (the Field pattern of c-field-7). */
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
} & Omit<ComponentProps<typeof Input>, "value" | "onChange">) {
  const id = useId()
  return (
    <Field data-invalid={error ? true : undefined}>
      <FieldLabel htmlFor={id}>{label}</FieldLabel>
      <Input id={id} value={value} onChange={(event) => onChange(event.target.value)} aria-invalid={error ? true : undefined} autoComplete="off" spellCheck={false} {...input} />
      {error ? <FieldError>{error}</FieldError> : hint ? <FieldDescription>{hint}</FieldDescription> : null}
    </Field>
  )
}
