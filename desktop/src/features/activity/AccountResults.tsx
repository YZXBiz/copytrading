import { CheckCircle2Icon, CircleAlertIcon, CircleDashedIcon, ClockIcon, MinusCircleIcon, XCircleIcon, type LucideIcon } from "lucide-react"
import type { SourceActivity } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { FramePanel } from "@/components/reui/frame"
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
    <div className="flex flex-col gap-2">
      <p className="flex items-start gap-2 leading-snug font-medium tabular-nums">
        <Icon aria-hidden className={cn("mt-0.5 size-4 shrink-0", className)} />
        {result.headline}
      </p>
      {result.facts.length > 0 && (
        <dl className="divide-border flex flex-col divide-y text-sm">
          {result.facts.map((fact) => (
            <div key={fact.label} className="flex items-baseline justify-between gap-6 py-1.5 first:pt-0 last:pb-0">
              <dt className="text-muted-foreground">{fact.label}</dt>
              <dd className="text-end tabular-nums">{fact.value}</dd>
            </div>
          ))}
        </dl>
      )}
      {result.note && <p className="text-muted-foreground text-sm">{result.note}</p>}
    </div>
  )
}

function AccountPanel({ account }: { account: AccountOutcome }) {
  return (
    <FramePanel role="group" aria-label={`Account ${account.id}`} className="flex flex-col gap-4">
      <div className="flex items-center justify-between gap-2 text-sm font-medium">
        <span className="truncate">{account.id}</span>
        {account.environment === "live" ? <Badge variant="warning-light">Live</Badge> : <Badge variant="outline">Paper</Badge>}
      </div>
      {account.results.map((result, index) => (
        <ResultBlock key={index} result={result} />
      ))}
    </FramePanel>
  )
}

/** What each account did with the post, one panel each, takeaway first: one line on what happened, a few facts behind it, and a note only when a question is left. */
export function AccountResults({ post, now, accountId }: { post: SourceActivity; now: Date; accountId: string | null }) {
  const shown = cardOutcome(post, now).accounts.filter((a) => accountId === null || a.id === accountId)
  if (shown.length === 0) {
    // "Yet" only while the trade is still on its way to the accounts.
    const onTheWay = post.decision === "trade" && post.delivery_status !== "delivered"
    return (
      <FramePanel>
        <p className="text-muted-foreground flex items-center gap-2 text-sm">
          <CircleDashedIcon aria-hidden className="size-4" />
          {onTheWay ? "No account has acted on this post yet." : "No account was asked to act on this post."}
        </p>
      </FramePanel>
    )
  }
  return shown.map((account) => <AccountPanel key={account.id} account={account} />)
}
