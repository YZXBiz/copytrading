import { useState } from "react"
import { CalendarIcon } from "lucide-react"
import { format, parseISO } from "date-fns"
import { Button } from "@/components/ui/button"
import { Calendar } from "@/components/ui/calendar"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { shiftDay } from "./post-bucket"

/** dashboard-7's date picker button and popover, for one day: the cards show the day chosen (a key like "2026-11-04"). */
export function DayPicker({ value, today, onChange }: { value: string; today: string; onChange: (day: string) => void }) {
  const [open, setOpen] = useState(false)
  const pick = (day: string) => {
    onChange(day)
    setOpen(false)
  }
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger
        render={
          <Button type="button" size="sm" variant="outline" aria-label="Choose the day" className="group/pick-date w-44 max-w-full justify-between leading-none font-normal tabular-nums">
            <span className="truncate">{format(parseISO(value), "MMM d, yyyy")}</span>
            <CalendarIcon className="text-muted-foreground/80 group-hover/pick-date:text-foreground shrink-0 transition-colors" aria-hidden="true" />
          </Button>
        }
      />
      <PopoverContent align="end" className="w-auto p-0">
        <div className="flex flex-col">
          <Calendar
            mode="single"
            selected={parseISO(value)}
            onSelect={(date) => date && pick(format(date, "yyyy-MM-dd"))}
            defaultMonth={parseISO(value)}
            disabled={{ after: parseISO(today) }}
          />
          <div className="border-border flex items-center justify-between gap-2 border-t px-3 py-1.5">
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
