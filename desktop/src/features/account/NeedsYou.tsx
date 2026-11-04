import { BellIcon } from "lucide-react"
import { Alert, AlertAction, AlertDescription, AlertTitle } from "@/components/reui/alert"
import { Badge } from "@/components/reui/badge"
import { Button } from "@/components/ui/button"
import { endOfTradingDay, untilText } from "@/features/activity/deadline"
import { namedBuyNote } from "@/features/activity/outcome"
import { PostPicture } from "@/features/activity/PostPicture"
import { pictureOf, readableText } from "@/features/activity/reading"
import { type WaitingCall, callPhrase, gainLine } from "./waiting"
import type { Recent } from "./skipped-calls"

/** The button's word: enter the trade yourself, approve what the account held, or copy what the post called. */
const copyLabel = (call: WaitingCall) => (call.calls.length === 0 ? "Enter Trade…" : call.awaitsApproval ? "Approve…" : "Copy…")

/**
 * One waiting call: what copying places as the title, the guru's own words as one quoted line (or their picture when
 * they wrote none), what it is worth against the buy it sells, until when it can be copied, and the two answers.
 */
function CallTicket({
  call,
  canCopy,
  now,
  onCopy,
  onSkip,
}: {
  call: WaitingCall
  canCopy: boolean
  now: Date
  onCopy: () => void
  onSkip: () => void
}) {
  const first = call.calls[0]
  const title = first ? callPhrase(first) + (call.calls.length > 1 ? ` and ${call.calls.length - 1} more` : "") : "Enter the trade yourself"
  const held = namedBuyNote(call.source)
  const gain = first ? gainLine(first) : null
  // The post is untrusted Discord text: rendered as text, never as HTML. A relay's bare label is not words, so the picture shows instead.
  const said = readableText(call.source)
  const picture = pictureOf(call.source)
  return (
    <Alert variant="warning" aria-label="Call waiting for you">
      <BellIcon aria-hidden />
      <AlertTitle className="line-clamp-none">{title}</AlertTitle>
      <AlertDescription>
        {said && <p className="text-foreground line-clamp-2 break-words">“{said}”</p>}
        {picture && <PostPicture attachment={picture} className="max-h-24" />}
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 tabular-nums">
          <span>{untilText(endOfTradingDay(call.source.source_at), now)}</span>
          {/* A sell held for its buy price has no buy to gain on: it says what came of that buy. */}
          {held ? (
            <span>{held}</span>
          ) : (
            gain && <Badge variant={gain.change < 0 ? "destructive-light" : "success-light"}>{gain.line}</Badge>
          )}
        </div>
      </AlertDescription>
      <AlertAction>
        <Button type="button" size="xs" variant="ghost" onClick={onSkip}>
          Skip
        </Button>
        <Button type="button" size="xs" disabled={!canCopy} onClick={onCopy} title={canCopy ? undefined : "Copying is off, so nothing can be placed yet."}>
          {copyLabel(call)}
        </Button>
      </AlertAction>
    </Alert>
  )
}

/** The calls this account holds for the owner, newest first, each with Skip and Copy, until its trading day ends. Nothing shows when nothing waits. */
export function NeedsYou({
  calls,
  canCopy,
  now,
  recent,
  onCopy,
  onSkip,
  onUndo,
}: {
  calls: WaitingCall[]
  canCopy: boolean
  now: Date
  recent: Recent | null
  onCopy: (call: WaitingCall) => void
  onSkip: (call: WaitingCall) => void
  onUndo: () => void
}) {
  if (calls.length === 0 && !recent) return null
  return (
    <section aria-label="Calls waiting for you" className="flex flex-col gap-3">
      {recent && (
        <div className="text-muted-foreground flex items-baseline gap-3 py-1 text-sm">
          <span className="truncate">{recent.text ? `Skipped “${recent.text}”` : "Skipped"}</span>
          <Button type="button" size="xs" variant="ghost" onClick={onUndo}>
            Undo
          </Button>
        </div>
      )}
      {calls.map((call) => (
        <CallTicket key={call.source.sequence} call={call} canCopy={canCopy} now={now} onCopy={() => onCopy(call)} onSkip={() => onSkip(call)} />
      ))}
    </section>
  )
}
