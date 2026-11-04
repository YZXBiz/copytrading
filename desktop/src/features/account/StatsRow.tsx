import type { AccountOverview } from "../../../shared/contract"
import { Frame } from "@/components/reui/frame"
import { money } from "@/lib/format"
import { Stat } from "./Stat"

/** What the account can spend and what CopyTrading has put to work; the balance itself leads the chart above. */
export function StatsRow({ account }: { account: AccountOverview }) {
  const b = account.balance
  return (
    <Frame spacing="sm" className="grid grid-cols-1 sm:grid-cols-3">
      <Stat label="Cash" value={money(b?.cash)} />
      <Stat label="Buying power" value={money(b?.buying_power)} />
      <Stat
        label="Invested by CopyTrading"
        value={money(account.total_exposure_usd ?? "0")}
        note={account.pending_orders ? `${account.pending_orders} orders waiting` : undefined}
      />
    </Frame>
  )
}
