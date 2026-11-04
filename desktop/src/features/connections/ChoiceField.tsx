import { useId } from "react"
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"

/** A choice between a few words, one always picked (a ToggleGroup in a Field). */
export function ChoiceField<T extends string>({
  label,
  hint,
  value,
  choices,
  onChange,
  disabled,
}: {
  label: string
  hint?: string
  value: T
  choices: { value: T; label: string }[]
  onChange: (value: T) => void
  disabled?: boolean
}) {
  const id = useId()
  return (
    <Field>
      <FieldLabel id={id}>{label}</FieldLabel>
      <ToggleGroup
        aria-labelledby={id}
        variant="outline"
        size="sm"
        spacing={0}
        value={[value]}
        disabled={disabled}
        onValueChange={(next) => next[0] && onChange(next[0] as T)}
        className="w-fit"
      >
        {choices.map((choice) => (
          <ToggleGroupItem key={choice.value} value={choice.value}>
            {choice.label}
          </ToggleGroupItem>
        ))}
      </ToggleGroup>
      {hint && <FieldDescription>{hint}</FieldDescription>}
    </Field>
  )
}
