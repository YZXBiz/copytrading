import { format, parseISO } from "date-fns"
import { DayPicker } from "./DayPicker"
import styles from "./activity.module.css"

/** The day and what needs the reader on the left, the day picker on the right. */
export function ActivityHeader({ day, today, status, onDayChange }: { day: string; today: string; status: string; onDayChange: (day: string) => void }) {
  return (
    <header className={styles.header} aria-label="Activity header">
      <div className={styles.headerText}>
        {/* The app's header already shows the page's name; the heading stays for screen readers. */}
        <h1 id="activity-title" className={styles.srOnly}>
          Activity
        </h1>
        <p>{format(parseISO(day), "EEEE, MMM d, yyyy")}</p>
        <p role="status" aria-live="polite">
          {status}
        </p>
      </div>
      <DayPicker value={day} today={today} onChange={onDayChange} />
    </header>
  )
}
