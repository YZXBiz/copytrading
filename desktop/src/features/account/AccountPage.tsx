import { useRef, useState } from "react"
import type { AccountOverview, Position } from "../../../shared/contract"
import { readableText } from "@/features/activity/reading"
import { readClock } from "@/lib/clock"
import { useResult } from "@/lib/use-result"
import styles from "./account.module.css"
import { AccountHeader } from "./AccountHeader"
import { ControlNotes, useAccountControl } from "./AccountControl"
import { AccountNotices } from "./AccountNotices"
import { BalanceHero } from "./balance-panel/BalanceHero"
import { useDeepLink } from "./deep-link"
import { Figures } from "./Figures"
import { Holdings, sellable } from "./Holdings"
import { LimitMeters } from "./LimitMeters"
import { LimitsSheet } from "./LimitsSheet"
import { type LotSaleTarget, LotSaleSheet } from "./LotSaleSheet"
import { ManualReviewSheet } from "./ManualReviewSheet"
import { heldPositions } from "./model"
import { type PostFilter, sourceKey } from "./post-rows"
import { PostsTable } from "./PostsTable"
import { useSkippedCalls } from "./skipped-calls"
import { type WaitingCall, openCall } from "./waiting"

/** The account page: its state and the one action (Stop or Start copying), the balance, the figures, limits beside holdings, then the posts. */
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
  const posts = useResult(() => window.copytrading.read.getSourceActivity(), id, 15_000)
  const limits = useResult(() => window.copytrading.read.getLimits({ account_id: id }), id, 15_000)
  const status = useResult(() => window.copytrading.read.getStatus(), id, 5000)
  const skipped = useSkippedCalls()
  const [review, setReview] = useState<WaitingCall | null>(null)
  const [sale, setSale] = useState<LotSaleTarget | null>(null)
  const [editingLimits, setEditingLimits] = useState(false)
  const [limitsSaved, setLimitsSaved] = useState(false)
  const [filter, setFilter] = useState<PostFilter>("all")
  const [version, setVersion] = useState(0)
  const table = useRef<HTMLDivElement>(null)

  const guru = limits.status === "ready" && limits.data ? limits.data.guru : null
  const copyingStatus = status.status === "ready" ? status.data : null
  const canEditLimits = limits.status === "ready" && limits.data !== null
  const calls =
    posts.status === "ready"
      ? posts.data.items
          .flatMap((post) => openCall(post, { skipped: skipped.has(sourceKey(post)), now }) ?? [])
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

  /** Something may have changed in the engine: read the account, its posts, its limits, its state and its balance history again. */
  const changed = () => {
    onRefresh()
    posts.retry()
    limits.retry()
    status.retry()
    setVersion((v) => v + 1)
  }
  const control = useAccountControl(account, status, changed)

  const saleTarget = (position: Position, lot: Position["lots"][number]): LotSaleTarget => ({
    accountId: id,
    environment: account.environment,
    symbol: position.symbol,
    lot,
    guruName: guru,
    currentPrice: position.current_price,
  })

  return (
    <div className={styles.page}>
      <AccountHeader
        account={account}
        guru={guru}
        control={control}
        canEditLimits={canEditLimits}
        onEditLimits={() => setEditingLimits(true)}
        onRefresh={changed}
        onOpenConnections={onOpenConnections}
      />
      <ControlNotes control={control} saved={limitsSaved} />
      <AccountNotices account={account} status={copyingStatus} onResolved={changed} />
      <BalanceHero account={account} version={version} onRefresh={changed} />
      <Figures
        account={account}
        waiting={calls.length}
        onShowWaiting={() => {
          setFilter("waiting")
          table.current?.scrollIntoView({ behavior: "smooth", block: "start" })
        }}
      />
      <div className={styles.split}>
        <LimitMeters account={account} limits={limits} onOpenConnections={onOpenConnections} />
        <Holdings account={account} onRefresh={onRefresh} onSell={(position, lot) => setSale(saleTarget(position, lot))} />
      </div>
      <div ref={table}>
        <PostsTable
          accountId={id}
          posts={posts}
          calls={calls}
          canCopy={copyingStatus?.state === "running" || copyingStatus?.state === "degraded"}
          now={now}
          recent={skipped.recent}
          skipped={skipped.has}
          filter={filter}
          onFilterChange={setFilter}
          onCopy={setReview}
          onSkip={(call) => skipped.skip(sourceKey(call.source), readableText(call.source))}
          onSkipAll={() => skipped.skipAll(calls.map((call) => ({ sourceId: sourceKey(call.source), text: readableText(call.source) })))}
          onUndo={skipped.undo}
        />
      </div>
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
