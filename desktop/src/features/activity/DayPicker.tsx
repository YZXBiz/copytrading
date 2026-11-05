import { useMemo } from "react"
import { DatePicker } from "@/components/arc/date-picker/date-picker"
import { Button } from "@/components/arc/button/button"
import { shiftDay } from "./post-bucket"
import styles from "./activity.module.css"

/** A day key like "2026-11-04" as that day in the reader's own calendar. */
const dayOf = (key: string) => {
  const [year, month, day] = key.split("-").map(Number)
  return new Date(year!, month! - 1, day!)
}
const keyOf = (date: Date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`

/** One day, chosen in a calendar: the cards show the day chosen. A day after today is not offered. */
export function DayPicker({ value, today, onChange }: { value: string; today: string; onChange: (day: string) => void }) {
  const selected = useMemo(() => dayOf(value), [value])
  const latest = useMemo(() => dayOf(today), [today])
  return (
    <div className={styles.picker}>
      <Button variant="ghost" size="sm" onClick={() => onChange(shiftDay(today, -1))} disabled={value === shiftDay(today, -1)}>
        Yesterday
      </Button>
      <DatePicker
        className={styles.dayField}
        label="Day"
        value={selected}
        maxDate={latest}
        showToday
        onChange={(date) => {
          if (date) onChange(keyOf(date) > today ? today : keyOf(date))
        }}
      />
    </div>
  )
}
