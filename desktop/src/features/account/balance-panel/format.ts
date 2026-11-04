import { getTimeZone } from "@/lib/time-zone"

const USD = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
})
const USD_SIGNED = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
  signDisplay: "exceptZero",
})
const USD_AXIS = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  notation: "compact",
  maximumFractionDigits: 1,
})
const PERCENT = new Intl.NumberFormat("en-US", {
  style: "percent",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
})
const PERCENT_SIGNED = new Intl.NumberFormat("en-US", {
  style: "percent",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
  signDisplay: "exceptZero",
})

/** "$24,847.83" */
export const formatUsd = (value: number) => USD.format(value)
/** "+$312.40", "-$88.10" */
export const formatSignedUsd = (value: number) => USD_SIGNED.format(value)
/** "$24.5K" */
export const formatAxis = (value: number) => USD_AXIS.format(value)
/** "+1.26%" */
export const formatSignedPercent = (ratio: number) =>
  PERCENT_SIGNED.format(ratio)
/** "1.26%" */
export const formatPercent = (ratio: number) => PERCENT.format(ratio)
/** A gap in percentage points: "+2.13 pts" */
export const formatPoints = (ratio: number) =>
  `${PERCENT_SIGNED.format(ratio).replace("%", "")} pts`

// Dates read in the zone chosen in Settings, not the block's fixed UTC.
const dateFormat = (options: Intl.DateTimeFormatOptions, time: number) =>
  new Intl.DateTimeFormat("en-US", { timeZone: getTimeZone(), ...options }).format(time)

/** "Oct 2" */
export const formatDay = (time: number) =>
  dateFormat({ month: "short", day: "numeric" }, time)
/** "Oct 16, 2026" */
export const formatFullDay = (time: number) =>
  dateFormat({ month: "short", day: "numeric", year: "numeric" }, time)
/** "Fri, Oct 16, 2026, 1:41 PM": a close's own time, as the readout says it. */
export const formatWeekday = (time: number) =>
  dateFormat(
    {
      weekday: "short",
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
    },
    time
  )
