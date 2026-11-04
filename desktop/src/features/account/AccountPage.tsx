import { useState } from "react"
import type { AccountOverview } from "../../../shared/contract"
import { readClock } from "@/lib/clock"
import { useResult } from "@/lib/use-result"
import { AccountHeader } from "./AccountHeader"
import { BalanceChart } from "./BalanceChart"
import { LimitsPanel } from "./LimitsPanel"
import { NeedsYou } from "./NeedsYou"
import { PositionsTable } from "./PositionsTable"
import { RecentPosts } from "./RecentPosts"
import { StatsRow } from "./StatsRow"
import { isWaiting } from "./model"

export function AccountPage({
  account,
  onRefresh,
  onOpenConnections,
}: {
  account: AccountOverview
  onRefresh: () => void
  onOpenConnections: () => void
}) {
  const id = account.account_id
  // One reading of the clock per visit: whether a post still waits depends on its trading day.
  const [now] = useState(readClock)
  const posts = useResult(() => window.copytrading.read.getSourceActivity(), id)
  const limits = useResult(() => window.copytrading.read.getLimits({ account_id: id }), id)
  const waiting = posts.status === "ready" ? posts.data.items.filter((post) => isWaiting(post, now)) : []
  const guru = limits.status === "ready" && limits.data ? limits.data.guru : null

  return (
    <div className="flex flex-col gap-6">
      <AccountHeader account={account} guru={guru} />
      <NeedsYou waiting={waiting} />
      <StatsRow account={account} />
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_320px]">
        <BalanceChart accountId={id} />
        <LimitsPanel account={account} limits={limits} onOpenConnections={onOpenConnections} />
      </div>
      <PositionsTable account={account} onRefresh={onRefresh} />
      <RecentPosts accountId={id} posts={posts} now={now} />
    </div>
  )
}
