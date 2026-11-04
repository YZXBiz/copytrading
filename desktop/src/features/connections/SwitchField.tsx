import { useId } from "react"
import { Field, FieldContent, FieldDescription, FieldTitle } from "@/components/ui/field"
import { Switch } from "@/components/ui/switch"

/** A setting that is on or off, with what it does under its name (the horizontal Field with a Switch of c-field-7). */
export function SwitchField({
  title,
  hint,
  checked,
  onChange,
  disabled,
}: {
  title: string
  hint: string
  checked: boolean
  onChange: (checked: boolean) => void
  disabled?: boolean
}) {
  const id = useId()
  return (
    <Field orientation="horizontal">
      <FieldContent>
        <FieldTitle id={`${id}-title`}>{title}</FieldTitle>
        <FieldDescription>{hint}</FieldDescription>
      </FieldContent>
      <Switch aria-labelledby={`${id}-title`} checked={checked} onCheckedChange={onChange} disabled={disabled} />
    </Field>
  )
}
