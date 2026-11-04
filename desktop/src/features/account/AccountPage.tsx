import { useState } from "react"
import type { AccountOverview, Position } from "../../../shared/contract"
import { readableText } from "@/features/activity/reading"
import { readClock } from "@/lib/clock"
import { useResult } from "@/lib/use-result"
import { AccountHeader } from "./AccountHeader"
import { AccountNotices } from "./AccountNotices"
import { BalanceChart } from "./BalanceChart"
import { useDeepLink } from "./deep-link"
import { LimitsPanel } from "./LimitsPanel"
import { LimitsSheet } from "./LimitsSheet"
import { type LotSaleTarget, LotSaleSheet } from "./LotSaleSheet"
import { ManualReviewSheet } from "./ManualReviewSheet"
import { heldPositions } from "./model"
import { NeedsYou } from "./NeedsYou"
import { PositionsTable, sellable } from "./PositionsTable"
import { RecentPosts } from "./RecentPosts"
import { StatsRow } from "./StatsRow"
import { useSkippedCalls } from "./skipped-calls"
import { type WaitingCall, openCall } from "./waiting"

export function AccountPage({
  account,
  accounts,
  onRefresh,
  onOpenConnections,
}: {
  account: AccountOverview
  /** Every account, for the ones a post reached. */
  accounts: AccountOverview[]
  onRefresh: () => void
  onOpenConnections: () => void
}) {
  const id = account.account_id
  // One reading of the clock per visit: whether a post still waits depends on its trading day.
  const [now] = useState(readClock)
  const posts = useResult(() => window.copytrading.read.getSourceActivity(), id)
  const limits = useResult(() => window.copytrading.read.getLimits({ account_id: id }), id)
  const status = useResult(() => window.copytrading.read.getStatus(), id)
  const skipped = useSkippedCalls()
  const [review, setReview] = useState<WaitingCall | null>(null)
  const [sale, setSale] = useState<LotSaleTarget | null>(null)
  const [editingLimits, setEditingLimits] = useState(false)
  const [limitsSaved, setLimitsSaved] = useState(false)

  const guru = limits.status === "ready" && limits.data ? limits.data.guru : null
  const copyingStatus = status.status === "ready" ? status.data : null
  const calls =
    posts.status === "ready"
      ? posts.data.items
          .flatMap((post) => openCall(post, { skipped: skipped.has(post.source_id ?? String(post.sequence)), now }) ?? [])
          .filter((call) => call.accountIds.includes(id))
          .sort((a, b) => b.source.source_at.localeCompare(a.source.source_at))
      : []

  useDeepLink(posts.status === "ready" && limits.status !== "loading", (sheet) => {
    if (sheet === "limits") setEditingLimits(true)
    if (sheet === "review") setReview(calls[0] ?? null)
    if (sheet === "sale") {
      const position = heldPositions(account).find((p) => sellable(p).length > 0)
      const lot = position && sellable(position)[0]
      if (position && lot) setSale(saleTarget(position, lot))
    }
  })

  /** Something may have changed in the engine: read the account, its posts, its limits and its state again. */
  const changed = () => {
    onRefresh()
    posts.retry()
    limits.retry()
    status.retry()
  }

  const saleTarget = (position: Position, lot: Position["lots"][number]): LotSaleTarget => ({
    accountId: id,
    environment: account.environment,
    symbol: position.symbol,
    lot,
    guruName: guru,
    currentPrice: position.current_price,
  })

  return (
    <div className="flex flex-col gap-6">
      <AccountHeader account={account} status={status} saved={limitsSaved} onChanged={changed} />
      <AccountNotices account={account} status={copyingStatus} onResolved={changed} />
      <NeedsYou
        calls={calls}
        canCopy={copyingStatus?.state === "running" || copyingStatus?.state === "degraded"}
        now={now}
        recent={skipped.recent}
        onCopy={setReview}
        onSkip={(call) => skipped.skip(call.source.source_id ?? String(call.source.sequence), readableText(call.source))}
        onUndo={skipped.undo}
      />
      <div className="grid grid-cols-1 items-start gap-6 lg:grid-cols-[minmax(0,1fr)_320px]">
        <BalanceChart account={account} />
        <LimitsPanel account={account} limits={limits} onOpenConnections={onOpenConnections} onEdit={() => setEditingLimits(true)} />
      </div>
      <StatsRow account={account} />
      <PositionsTable
        account={account}
        onRefresh={onRefresh}
        onSell={(position, lot) => setSale(saleTarget(position, lot))}
      />
      <RecentPosts accountId={id} posts={posts} now={now} />
      {review && (
        <ManualReviewSheet
          source={review.source}
          call={review}
          accounts={accounts}
          guruName={guru}
          now={now}
          onClose={() => {
            setReview(null)
            changed()
          }}
        />
      )}
      {sale && (
        <LotSaleSheet
          target={sale}
          onClose={() => {
            setSale(null)
            changed()
          }}
        />
      )}
      {editingLimits && (
        <LimitsSheet
          accountId={id}
          onClose={(saved) => {
            setEditingLimits(false)
            if (saved) {
              setLimitsSaved(true)
              changed()
            }
          }}
        />
      )}
    </div>
  )
}
