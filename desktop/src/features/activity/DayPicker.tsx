import { useCallback, useMemo, useState } from "react"
import { Calendar01Icon } from "@/components/icons/Calendar01Icon"
import { format, parseISO } from "date-fns"
import { DateSelector, type DateSelectorValue } from "@/components/reui/date-selector"
import { Button } from "@/components/ui/button"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { shiftDay } from "./post-bucket"

const DAY_KEY = "yyyy-MM-dd"

/** One day, chosen in a calendar: the cards show the day chosen (a key like "2026-11-04"). A day after today is today. */
export function DayPicker({ value, today, onChange }: { value: string; today: string; onChange: (day: string) => void }) {
  const [open, setOpen] = useState(false)
  const pick = (day: string) => {
    onChange(day)
    setOpen(false)
  }
  // The selector reports its value on every render and when it opens; only a different day is a pick.
  const selected = useMemo<DateSelectorValue>(() => ({ period: "day", operator: "is", startDate: parseISO(value) }), [value])
  const onSelect = useCallback(
    (next: DateSelectorValue) => {
      if (!next.startDate) return
      const day = format(next.startDate, DAY_KEY)
      if (day !== value) {
        onChange(day > today ? today : day)
        setOpen(false)
      }
    },
    [value, today, onChange],
  )
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger
        render={
          <Button type="button" size="sm" variant="outline" aria-label="Choose the day" className="group/pick-date w-44 max-w-full justify-between leading-none font-normal tabular-nums">
            <span className="truncate">{format(parseISO(value), "MMM d, yyyy")}</span>
            <Calendar01Icon className="text-muted-foreground/80 group-hover/pick-date:text-foreground shrink-0 transition-colors" aria-hidden="true" />
          </Button>
        }
      />
      <PopoverContent align="end" className="w-auto p-3">
        <div className="flex flex-col gap-3">
          <DateSelector value={selected} onChange={onSelect} allowRange={false} presetMode="is" periodTypes={["day"]} showInput={false} showTwoMonths={false} className="sm:w-72 [&>div:first-child]:hidden" />
          <div className="border-border flex items-center justify-between gap-2 border-t pt-2">
            <Button type="button" size="sm" variant="ghost" className="text-muted-foreground" onClick={() => pick(shiftDay(today, -1))}>
              Yesterday
            </Button>
            <Button type="button" size="sm" variant="outline" onClick={() => pick(today)}>
              Today
            </Button>
          </div>
        </div>
      </PopoverContent>
    </Popover>
  )
}
