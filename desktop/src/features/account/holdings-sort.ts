import type { AccountOverview } from "../../../shared/contract"

type Position = AccountOverview["positions"][number]

export type HoldingsSort = "value" | "gain" | "name"
export const HOLDINGS_SORTS: { value: HoldingsSort; label: string }[] = [
  { value: "value", label: "Value" },
  { value: "gain", label: "Gain" },
  { value: "name", label: "A–Z" },
]

const num = (text: string | null | undefined) => (text === null || text === undefined || text === "" || !Number.isFinite(Number(text)) ? null : Number(text))

/** Biggest first for value and gain, a to z for name; a position the broker gave no figure for comes last. Uses the broker's figures, so a price tick never reorders the list. */
export function sortHoldings(held: Position[], by: HoldingsSort): Position[] {
  const key = (p: Position) => (by === "value" ? num(p.market_value) : num(p.unrealized_plpc))
  return [...held].sort((a, b) => {
    if (by === "name") return a.symbol.localeCompare(b.symbol)
    const [x, y] = [key(a), key(b)]
    if (x === null || y === null) return x === y ? a.symbol.localeCompare(b.symbol) : x === null ? 1 : -1
    return y - x || a.symbol.localeCompare(b.symbol)
  })
}
