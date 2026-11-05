import { useMemo } from "react"
import { Globe02Icon } from "@/components/icons/Globe02Icon"
import { Combobox, ComboboxContent, ComboboxEmpty, ComboboxInput, ComboboxItem, ComboboxList } from "@/components/ui/combobox"
import { Field } from "@/components/ui/field"
import { InputGroupAddon } from "@/components/ui/input-group"
import { NEW_YORK, allTimeZones, setTimeZone, useTimeZone, zoneLabel } from "@/lib/time-zone"

interface Choice {
  /** The IANA name, or undefined for the Mac's own zone. */
  zone: string | undefined
  label: string
}

/** Automatic, New York's market time, then every zone by city and name. Typing narrows the list. */
export function TimeZoneField() {
  const zone = useTimeZone()
  const choices = useMemo<Choice[]>(() => {
    const at = new Date()
    const rest = allTimeZones().filter((z) => z !== NEW_YORK)
    return [undefined, NEW_YORK, ...rest].map((z) => ({ zone: z, label: zoneLabel(z, at) }))
  }, [])
  const selected = choices.find((c) => c.zone === zone) ?? { zone, label: zoneLabel(zone) }
  return (
    <Field className="w-72">
      <Combobox
        items={choices}
        value={selected}
        onValueChange={(choice: Choice | null) => choice && setTimeZone(choice.zone)}
        isItemEqualToValue={(a: Choice, b: Choice) => a.zone === b.zone}
        itemToStringLabel={(choice: Choice) => choice.label}
      >
        <ComboboxInput aria-label="Show times in" placeholder="City or time zone">
          <InputGroupAddon>
            <Globe02Icon className="text-muted-foreground size-4" aria-hidden />
          </InputGroupAddon>
        </ComboboxInput>
        <ComboboxContent>
          <ComboboxEmpty>No time zone matches.</ComboboxEmpty>
          <ComboboxList>
            {(choice: Choice) => (
              <ComboboxItem key={choice.zone ?? "auto"} value={choice}>
                {choice.label}
              </ComboboxItem>
            )}
          </ComboboxList>
        </ComboboxContent>
      </Combobox>
    </Field>
  )
}
