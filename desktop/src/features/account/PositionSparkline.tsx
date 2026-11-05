import type { Bar } from "../../../shared/contract"
import { parseDec } from "./decimal"
import styles from "./account.module.css"

/** The day's direction: the session's last close against its first open. Null when there is nothing to compare. */
export function dayDirection(bars: Bar[]): "up" | "down" | null {
  const first = bars[0] && parseDec(bars[0].open) !== null ? Number(bars[0].open) : null
  const last = bars.length > 0 && parseDec(bars[bars.length - 1]!.close) !== null ? Number(bars[bars.length - 1]!.close) : null
  if (first === null || last === null) return null
  return last >= first ? "up" : "down"
}

const W = 64
const H = 28

/** A one-day line for a held stock against its open, in the gain color or the loss color; nothing at all when it has no bars. */
export function PositionSparkline({ bars }: { bars: Bar[] | undefined }) {
  const direction = bars && bars.length >= 2 ? dayDirection(bars) : null
  // Holds its column, so the figures beside it line up row to row.
  if (!bars || direction === null) return <span className={styles.spark} aria-hidden="true" />

  const points = bars.map((bar) => Number(bar.close))
  const base = Number(bars[0]!.open)
  const lo = Math.min(base, ...points)
  const hi = Math.max(base, ...points)
  const span = hi - lo || 1
  const toY = (value: number) => (H - 3 - ((value - lo) / span) * (H - 6)).toFixed(2)
  const path = points.map((value, index) => `${index ? "L" : "M"}${((index / Math.max(1, points.length - 1)) * W).toFixed(2)} ${toY(value)}`).join("")
  return (
    <svg className={styles.spark} data-direction={direction} viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" aria-hidden="true">
      <line className={styles.sparkBase} x1="0" x2={W} y1={toY(base)} y2={toY(base)} vectorEffect="non-scaling-stroke" />
      <path className={styles.sparkLine} d={path} vectorEffect="non-scaling-stroke" />
    </svg>
  )
}
