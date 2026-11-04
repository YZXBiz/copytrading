import { ArrowDownIcon, ArrowUpIcon } from "lucide-react"
import { Badge } from "@/components/reui/badge"
import { money } from "@/lib/format"
import { dollars } from "@/lib/quantity"
import type { Holdings } from "./model"

/** What the owner holds from this guru's calls right now, as one sentence, then how that stands today. Nothing shows while nothing is held. */
export function GuruHoldingsLine({ holdings }: { holdings: Holdings | null }) {
  if (!holdings) return null
  const { cost, gain, stocks } = holdings
  const up = gain >= 0
  return (
    <p className="text-muted-foreground flex flex-wrap items-center gap-2 text-sm">
      Holding {dollars(String(Math.round(cost)))} in {stocks === 1 ? "1 stock" : `${stocks} stocks`} from these calls
      {cost > 0 && (
        <Badge variant={up ? "success-light" : "destructive-light"}>
          {up ? <ArrowUpIcon aria-hidden="true" /> : <ArrowDownIcon aria-hidden="true" />}
          {money(Math.abs(gain))} ({Math.abs((gain / cost) * 100).toFixed(1)}%)
        </Badge>
      )}
    </p>
  )
}
