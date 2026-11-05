import { useMemo } from "react"
import { Combobox } from "@/components/arc/combobox/combobox"
import { NEW_YORK, allTimeZones, setTimeZone, useTimeZone, zoneLabel } from "@/lib/time-zone"
import styles from "./settings.module.css"

const AUTOMATIC = "automatic"

/** Automatic, New York's market time, then every zone by city and name. Typing narrows the list. */
export function TimeZoneField() {
  const zone = useTimeZone()
  const options = useMemo(() => {
    const at = new Date()
    const rest = allTimeZones().filter((z) => z !== NEW_YORK)
    return [AUTOMATIC, NEW_YORK, ...rest].map((z) => ({ value: z, label: zoneLabel(z === AUTOMATIC ? undefined : z, at) }))
  }, [])
  const value = zone ?? AUTOMATIC
  const known = options.some((option) => option.value === value)
  return (
    <div className={styles.field}>
      <Combobox
        label="Show times in"
        options={known ? options : [{ value, label: zoneLabel(zone) }, ...options]}
        value={value}
        onValueChange={(next) => setTimeZone(next === AUTOMATIC ? undefined : next)}
        placeholder="City or time zone"
        emptyMessage="No time zone matches."
      />
    </div>
  )
}
