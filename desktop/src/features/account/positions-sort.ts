import type { AccountOverview } from "../../../shared/contract"

type Position = AccountOverview["positions"][number]

/** What the Positions list can be ordered by: the old columns' sorting, as the list's tabs. */
export const SORTS = [
  { value: "value", label: "Value" },
  { value: "gain", label: "Gain" },
  { value: "stock", label: "Stock" },
] as const

export type SortKey = (typeof SORTS)[number]["value"]

const num = (value: string | null | undefined) => Number(value ?? 0)

/** Value and gain run from the most down; stock runs A to Z. A new array: the account's own order is left alone. */
export function sortPositions(positions: Position[], key: SortKey): Position[] {
  const order: Record<SortKey, (a: Position, b: Position) => number> = {
    value: (a, b) => num(b.market_value) - num(a.market_value),
    gain: (a, b) => num(b.unrealized_plpc) - num(a.unrealized_plpc),
    stock: (a, b) => a.symbol.localeCompare(b.symbol),
  }
  return [...positions].sort(order[key])
}
