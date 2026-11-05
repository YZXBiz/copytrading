import type { ReactNode } from "react"
import { CircleDashedIcon } from "@/components/icons/CircleDashedIcon"
import type { SourceActivity } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { cn } from "@/lib/utils"
import { toneIcon } from "./OutcomeBadge"
import { type AccountOutcome, type Result, type Tone, cardOutcome } from "./outcome"

const COLOR: Record<Tone, string> = {
  positive: "text-success",
  caution: "text-warning",
  critical: "text-destructive",
  neutral: "text-muted-foreground",
  inactive: "text-muted-foreground",
}

/** One fact of a result, label over value: the audit log's detail row (solution-users-6). */
function DetailRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex min-w-0 flex-col gap-0.5">
      <dt className="text-muted-foreground text-xs">{label}</dt>
      <dd className="text-foreground flex min-w-0 items-center text-sm font-medium tabular-nums">{children}</dd>
    </div>
  )
}

function ResultBlock({ result }: { result: Result }) {
  const Icon = toneIcon(result.tone)
  return (
    <div className="space-y-3">
      <p className="flex items-start gap-2 text-sm leading-snug font-medium tabular-nums">
        <Icon aria-hidden className={cn("mt-0.5 size-4 shrink-0", COLOR[result.tone])} />
        {result.headline}
      </p>
      {result.facts.length > 0 && (
        <dl className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
          {result.facts.map((fact) => (
            <DetailRow key={fact.label} label={fact.label}>
              {fact.value}
            </DetailRow>
          ))}
        </dl>
      )}
      {result.note && <p className="text-muted-foreground text-xs leading-5">{result.note}</p>}
    </div>
  )
}

function AccountBlock({ account }: { account: AccountOutcome }) {
  return (
    <div role="group" aria-label={`Account ${account.id}`} className="space-y-3 border-t pt-2.5">
      <div className="flex items-center justify-between gap-2.5">
        <span className="min-w-0 truncate text-sm font-medium">{account.id}</span>
        {account.environment === "live" ? <Badge variant="warning-light">Live</Badge> : <Badge variant="outline">Paper</Badge>}
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
      <p className="text-muted-foreground flex items-center gap-2 border-t pt-2.5 text-xs">
        <CircleDashedIcon aria-hidden className="size-4" />
        {onTheWay ? "No account has acted on this post yet." : "No account was asked to act on this post."}
      </p>
    )
  }
  return shown.map((account) => <AccountBlock key={account.id} account={account} />)
}
