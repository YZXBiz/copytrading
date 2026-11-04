import type { AccountOverview } from "../../../shared/contract"
import { Frame } from "@/components/reui/frame"
import { money, signedMoney } from "@/lib/format"
import { Stat } from "./Stat"
import { dayChange } from "./model"

const GRID = "grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4"

export function StatsRow({ account }: { account: AccountOverview }) {
  const b = account.balance
  const change = dayChange(account)
  return (
    <Frame spacing="sm" className={GRID}>
      <Stat
        label="Balance"
        value={money(b?.equity)}
        delta={
          change && b
            ? { fraction: change.fraction, against: `${signedMoney(change.amount)} today · closed ${money(b.previous_close_equity)}` }
            : undefined
        }
        note={b ? undefined : "Not read from the broker yet"}
      />
      <Stat label="Cash" value={money(b?.cash)} note="Ready to spend" />
      <Stat label="Buying power" value={money(b?.buying_power)} note="Including margin" />
      <Stat
        label="Invested by CopyTrading"
        value={money(account.total_exposure_usd ?? "0")}
        note={account.pending_orders ? `${account.pending_orders} orders waiting` : "No orders waiting"}
      />
    </Frame>
  )
}
