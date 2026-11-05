import { format, parseISO } from "date-fns"
import { DayPicker } from "./DayPicker"

/** dashboard-7's header: the title, the day and a status line on the left, the day picker on the right. */
export function ActivityHeader({ day, today, status, onDayChange }: { day: string; today: string; status: string; onDayChange: (day: string) => void }) {
  return (
    <header className="flex min-h-9 w-full shrink-0 flex-col justify-between gap-2 pb-1 sm:flex-row sm:items-center" aria-label="Activity header">
      <div className="flex min-w-0 flex-col gap-0.5 sm:flex-row sm:items-center sm:gap-2">
        {/* The app's header already shows the page's name; the heading stays for screen readers. */}
        <h1 id="activity-title" className="sr-only">
          Activity
        </h1>
        <p className="text-muted-foreground truncate text-xs">{format(parseISO(day), "EEEE, MMM dd, yyyy")}</p>
        <span aria-hidden className="bg-muted-foreground/40 hidden size-1 shrink-0 rounded-full sm:block" />
        <p className="text-muted-foreground truncate text-xs" role="status" aria-live="polite">
          {status}
        </p>
      </div>
      <div className="flex shrink-0 items-center gap-2">
        <DayPicker value={day} today={today} onChange={onDayChange} />
      </div>
    </header>
  )
}
