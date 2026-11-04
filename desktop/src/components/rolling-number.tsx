import NumberFlow, { type Format } from "@number-flow/react"

// A readout that follows the pointer changes with every move, so it rolls faster than a figure that changes on a refresh.
const QUICK = { duration: 250, easing: "ease-out" } as const

/**
 * A figure whose digits roll to a new value, in the direction it moved. The first render shows the number as it is;
 * macOS "Reduce motion" shows each new value at once (NumberFlow reads the media query). The text is the formatter's
 * own: pass the same `Intl` options the page formats with (`balance-panel/format.ts`). A missing or non-numeric
 * value reads as a dash.
 */
export function RollingNumber({
  value,
  format,
  className,
  quick,
}: {
  value: number | null | undefined
  format: Format
  className?: string
  quick?: boolean
}) {
  if (value === null || value === undefined || !Number.isFinite(value)) return <span className={className}>—</span>
  return (
    <NumberFlow
      value={value}
      format={format}
      locales="en-US"
      className={className}
      {...(quick && { transformTiming: QUICK, spinTiming: QUICK })}
    />
  )
}
