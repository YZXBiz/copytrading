import { useId, type ReactNode } from "react"
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field"
import { Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger, SelectValue } from "@/components/ui/select"

export interface Choice {
  value: string
  label: string
}

/** One pick from a list, which may be grouped (the Select in a Field). */
export function SelectField({
  label,
  hint,
  value,
  groups,
  onChange,
  placeholder,
  disabled,
}: {
  label: string
  hint?: ReactNode
  value: string
  groups: { title?: string; choices: Choice[] }[]
  onChange: (value: string) => void
  placeholder?: string
  disabled?: boolean
}) {
  const id = useId()
  const items = groups.flatMap((g) => g.choices)
  return (
    <Field>
      <FieldLabel id={id}>{label}</FieldLabel>
      <Select value={value || null} items={items} onValueChange={(next) => next && onChange(next as string)} disabled={disabled}>
        <SelectTrigger aria-labelledby={id} className="w-full">
          <SelectValue placeholder={placeholder} />
        </SelectTrigger>
        <SelectContent>
          {groups.map((group) => (
            <SelectGroup key={group.title ?? "all"}>
              {group.title && <SelectLabel>{group.title}</SelectLabel>}
              {group.choices.map((choice) => (
                <SelectItem key={choice.value} value={choice.value}>
                  {choice.label}
                </SelectItem>
              ))}
            </SelectGroup>
          ))}
        </SelectContent>
      </Select>
      {hint && <FieldDescription>{hint}</FieldDescription>}
    </Field>
  )
}
