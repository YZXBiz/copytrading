import type { Position } from "../../../shared/contract"
import { money } from "@/lib/format"

/** The stops guarding a holding as one short line, lowest price first: "Stop $44.50", "Stops $38.40, $44.50"; null when it has none. */
export function stopLine(position: Pick<Position, "stops">): string | null {
  const prices = [...new Set((position.stops ?? []).map((s) => Number(s.stop_price)))].sort((a, b) => a - b)
  if (prices.length === 0) return null
  return `${prices.length > 1 ? "Stops" : "Stop"} ${prices.map((p) => money(p)).join(", ")}`
}
