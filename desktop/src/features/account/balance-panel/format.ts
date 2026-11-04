import { getTimeZone } from "@/lib/time-zone"

// The options are exported so the rolling numbers (components/rolling-number.tsx) format with exactly these.
export const USD_OPTIONS = { style: "currency", currency: "USD", minimumFractionDigits: 2, maximumFractionDigits: 2 } as const
export const USD_SIGNED_OPTIONS = { ...USD_OPTIONS, signDisplay: "exceptZero" } as const
/** The sidebar's "$2,700": cents cut off, never rounded up. */
export const USD_WHOLE_OPTIONS = { style: "currency", currency: "USD", maximumFractionDigits: 0, roundingMode: "trunc" } as const
export const PERCENT_SIGNED_OPTIONS = { style: "percent", minimumFractionDigits: 2, maximumFractionDigits: 2, signDisplay: "exceptZero" } as const

const USD = new Intl.NumberFormat("en-US", USD_OPTIONS)
const USD_SIGNED = new Intl.NumberFormat("en-US", USD_SIGNED_OPTIONS)
const PERCENT_SIGNED = new Intl.NumberFormat("en-US", PERCENT_SIGNED_OPTIONS)

/** "$24,847.83" */
export const formatUsd = (value: number) => USD.format(value)
/** "+$312.40", "-$88.10" */
export const formatSignedUsd = (value: number) => USD_SIGNED.format(value)
/** "+1.26%" */
export const formatSignedPercent = (ratio: number) =>
  PERCENT_SIGNED.format(ratio)
// Dates read in the zone chosen in Settings, not the block's fixed UTC.
const dateFormat = (options: Intl.DateTimeFormatOptions, time: number) =>
  new Intl.DateTimeFormat("en-US", { timeZone: getTimeZone(), ...options }).format(time)

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
