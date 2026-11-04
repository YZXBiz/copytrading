import { CheckCircle2Icon, CircleAlertIcon, CircleDashedIcon, ClockIcon, MinusCircleIcon, XCircleIcon, type LucideIcon } from "lucide-react"
import type { SourceActivity } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { cn } from "@/lib/utils"
import { type AccountOutcome, type Result, type Tone, cardOutcome } from "./outcome"

const MARK: Record<Tone, { icon: LucideIcon; className: string }> = {
  positive: { icon: CheckCircle2Icon, className: "text-success" },
  caution: { icon: CircleAlertIcon, className: "text-warning" },
  critical: { icon: XCircleIcon, className: "text-destructive" },
  neutral: { icon: ClockIcon, className: "text-muted-foreground" },
  inactive: { icon: MinusCircleIcon, className: "text-muted-foreground" },
}

function ResultBlock({ result }: { result: Result }) {
  const { icon: Icon, className } = MARK[result.tone]
  return (
    <div className="flex gap-2.5">
      <Icon aria-hidden className={cn("mt-0.5 size-4 shrink-0", className)} />
      <div className="flex min-w-0 flex-col gap-2">
        <p className="leading-snug font-medium tabular-nums">{result.headline}</p>
        {result.facts.length > 0 && (
          <dl className="grid grid-cols-[auto_1fr] gap-x-6 gap-y-1 text-sm">
            {result.facts.map((fact) => (
              <div key={fact.label} className="contents">
                <dt className="text-muted-foreground">{fact.label}</dt>
                <dd className="tabular-nums">{fact.value}</dd>
              </div>
            ))}
          </dl>
        )}
        {result.note && <p className="text-muted-foreground text-sm">{result.note}</p>}
      </div>
    </div>
  )
}

function AccountBlock({ account }: { account: AccountOutcome }) {
  return (
    <div role="group" aria-label={`Account ${account.id}`} className="flex flex-col gap-3">
      <div className="flex items-center gap-2 text-xs font-medium tracking-wide uppercase">
        <span className="text-muted-foreground">{account.id}</span>
        {account.environment === "live" ? <Badge variant="warning-light" size="sm">Live</Badge> : <span className="text-muted-foreground">Paper</span>}
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
      <p className="text-muted-foreground flex items-center gap-2 text-sm">
        <CircleDashedIcon aria-hidden className="size-4" />
        {onTheWay ? "No account has acted on this post yet." : "No account was asked to act on this post."}
      </p>
    )
  }
  return (
    <div className="flex flex-col gap-6">
      {shown.map((account) => (
        <AccountBlock key={account.id} account={account} />
      ))}
    </div>
  )
}
