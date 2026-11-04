import { BellIcon } from "lucide-react"
import { Alert, AlertAction, AlertDescription, AlertTitle } from "@/components/reui/alert"
import { Badge } from "@/components/reui/badge"
import { Button } from "@/components/ui/button"
import { dateTime, timeOfDay } from "@/lib/format"
import { deadlineText, endOfTradingDay } from "@/features/activity/deadline"
import { namedBuyNote } from "@/features/activity/outcome"
import { type WaitingCall, callPhrase, gainLine, waited } from "./waiting"
import type { Recent } from "./skipped-calls"

/** The button's word: enter the trade yourself, approve what the account held, or copy what the post called. */
const copyLabel = (call: WaitingCall) => (call.calls.length === 0 ? "Enter Trade…" : call.awaitsApproval ? "Approve…" : "Copy…")

/**
 * One waiting call as a ticket: how long it has waited and until when it can be copied, what copying places,
 * what that is worth against the buy it sells, the guru's own message, and the two answers.
 */
function CallTicket({
  call,
  guruName,
  canCopy,
  now,
  onCopy,
  onSkip,
}: {
  call: WaitingCall
  guruName: string | null
  canCopy: boolean
  now: Date
  onCopy: () => void
  onSkip: () => void
}) {
  const first = call.calls[0]
  const title = first ? callPhrase(first) + (call.calls.length > 1 ? ` and ${call.calls.length - 1} more` : "") : "Enter the trade yourself"
  const held = namedBuyNote(call.source)
  const gain = first ? gainLine(first) : null
  const sameDay = new Date(call.source.source_at).toDateString() === now.toDateString()
  return (
    <Alert variant="warning" aria-label="Call waiting for you">
      <BellIcon aria-hidden />
      <AlertTitle className="line-clamp-none">{title}</AlertTitle>
      <AlertDescription>
        <p>
          Waiting {waited(call.source.source_at, now)} · {deadlineText(endOfTradingDay(call.source.source_at), now)}
        </p>
        {/* A sell held for its buy price has no buy to gain on: it says what came of that buy. */}
        {held ? (
          <p>{held}</p>
        ) : (
          gain && (
            <Badge variant={gain.change < 0 ? "destructive-light" : "success-light"} className="tabular-nums">
              {gain.line}
            </Badge>
          )
        )}
        <div className="bg-background mt-1.5 w-full rounded-md border px-3 py-2">
          <div className="text-xs">
            <span className="text-foreground font-medium">{guruName ?? call.source.guru_id}</span>
            <span className="tabular-nums"> · {sameDay ? timeOfDay(call.source.source_at) : dateTime(call.source.source_at)}</span>
          </div>
          {/* The post is untrusted Discord text: rendered as text, never as HTML. */}
          <p className="text-foreground line-clamp-3 text-sm">{call.source.text || "A post with no words"}</p>
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

/** The calls this account holds for the owner, newest first, each a ticket with Skip and Copy, until its trading day ends. Nothing shows when nothing waits. */
export function NeedsYou({
  calls,
  guruName,
  canCopy,
  now,
  recent,
  onCopy,
  onSkip,
  onUndo,
}: {
  calls: WaitingCall[]
  guruName: string | null
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
        <CallTicket key={call.source.sequence} call={call} guruName={guruName} canCopy={canCopy} now={now} onCopy={() => onCopy(call)} onSkip={() => onSkip(call)} />
      ))}
    </section>
  )
}
