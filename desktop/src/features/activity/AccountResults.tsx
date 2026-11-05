import type { ReactNode } from "react"
import { CircleDashedIcon } from "@/components/icons/CircleDashedIcon"
import type { SourceActivity } from "../../../shared/contract"
import { Badge } from "@/components/arc/badge/badge"
import { toneColor, toneIcon } from "./OutcomeBadge"
import { type AccountOutcome, type Result, cardOutcome } from "./outcome"
import styles from "./post-detail.module.css"

/** One fact of a result, label over value. */
function DetailRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <dt>{label}</dt>
      <dd>{children}</dd>
    </div>
  )
}

function ResultBlock({ result }: { result: Result }) {
  const Icon = toneIcon(result.tone)
  return (
    <div className={styles.result}>
      <p className={styles.takeaway}>
        <Icon aria-hidden style={{ color: toneColor[result.tone] }} />
        {result.headline}
      </p>
      {result.facts.length > 0 && (
        <dl className={styles.rows}>
          {result.facts.map((fact) => (
            <DetailRow key={fact.label} label={fact.label}>
              {fact.value}
            </DetailRow>
          ))}
        </dl>
      )}
      {result.note && <p className={styles.note}>{result.note}</p>}
    </div>
  )
}

function AccountBlock({ account }: { account: AccountOutcome }) {
  return (
    <div role="group" aria-label={`Account ${account.id}`} className={styles.account}>
      <div className={styles.accountHead}>
        <strong>{account.id}</strong>
        {account.environment === "live" ? <Badge tone="warning">Live</Badge> : <Badge tone="neutral" outline>Paper</Badge>}
      </div>
      {account.results.map((result, index) => (
        <ResultBlock key={index} result={result} />
      ))}
    </div>
  )
}

/** What each account did with the post, takeaway first: one line on what happened, a few facts behind it, and a note only when a question is left. */
export function AccountResults({ post, now, accountId }: { post: SourceActivity; now: Date; accountId: string | null }) {
  const shown = cardOutcome(post, now).accounts.filter((a) => accountId === null || a.id === accountId)
  if (shown.length === 0) {
    // "Yet" only while the trade is still on its way to the accounts.
    const onTheWay = post.decision === "trade" && post.delivery_status !== "delivered"
    return (
      <p className={styles.nobody}>
        <CircleDashedIcon aria-hidden />
        {onTheWay ? "No account has acted on this post yet." : "No account was asked to act on this post."}
      </p>
    )
  }
  return shown.map((account) => <AccountBlock key={account.id} account={account} />)
}
