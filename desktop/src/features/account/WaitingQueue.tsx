import { type Ref, useMemo, useState } from "react"
import { Badge } from "@/components/arc/badge/badge"
import { InboxTriage } from "@/components/arc/blocks/inbox-triage/inbox-triage"
import { ReasoningBlock } from "@/components/arc/reasoning-block/reasoning-block"
import type { UndoToastHandle } from "@/components/arc/undo-toast/undo-toast"
import { Clock01Icon } from "@/components/icons/Clock01Icon"
import { Message01Icon } from "@/components/icons/Message01Icon"
import { endOfTradingDay, untilText } from "@/features/activity/deadline"
import { PostPicture } from "@/features/activity/PostPicture"
import { pictureOf, readableText } from "@/features/activity/reading"
import { SymbolMark } from "@/features/stock/TickerLink"
import { dateTime } from "@/lib/format"
import styles from "./account.module.css"
import { sourceKey } from "./post-rows"
import { UNDO_MS, useSkippedCalls } from "./skipped-calls"
import { type WaitingCall, callGain, copyLabel, meaningOf, whyWaits } from "./waiting"

const keyOf = (call: WaitingCall) => sourceKey(call.source)
const newestFirst = (a: WaitingCall, b: WaitingCall) => b.source.source_at.localeCompare(a.source.source_at)

/**
 * The calls waiting for the owner, answered one at a time: Copy opens the review, Skip takes the call off the list. A skip is
 * kept at once, as before, and can be undone for `UNDO_MS`; the skipped call stays in the queue, folded away, until then.
 */
export function WaitingQueue({
  calls,
  accountId,
  canCopy,
  now,
  onCopy,
  handle,
}: {
  calls: WaitingCall[]
  accountId: string
  canCopy: boolean
  now: Date
  onCopy: (call: WaitingCall) => void
  /** Skips a call by its key from outside the queue (Skip all). */
  handle: Ref<UndoToastHandle>
}) {
  const skipped = useSkippedCalls()
  const [held, setHeld] = useState<WaitingCall[]>([])
  // A skipped call has left `calls` at once, but its queue row has to stay for the toast's Undo to bring it back in place.
  const items = useMemo(() => [...calls, ...held.filter((h) => !calls.some((c) => keyOf(c) === keyOf(h)))].sort(newestFirst), [calls, held])
  const drop = (entries: { key: string }[]) => setHeld((current) => current.filter((h) => !entries.some((e) => e.key === keyOf(h))))

  if (items.length === 0) return null
  return (
    <InboxTriage<WaitingCall>
      items={items}
      getKey={keyOf}
      label="Calls waiting for you"
      noun={["call", "calls"]}
      duration={UNDO_MS}
      handle={handle}
      empty={<p>All answered</p>}
      onSkip={(entries) => {
        skipped.skip(entries.map((e) => e.key))
        setHeld((current) => [...current, ...entries.map((e) => e.item)])
      }}
      onUndo={(entries) => {
        skipped.unskip(entries.map((e) => e.key))
        drop(entries)
      }}
      onCommit={drop}
      answer={(call) => ({ label: copyLabel(call), onRun: () => onCopy(call), disabled: !canCopy, reason: "Copying is off, so nothing can be placed yet." })}
      row={(call) => {
        const said = readableText(call.source)
        const symbol = call.calls[0]?.symbol ?? call.source.instructions[0]?.symbol
        return {
          mark: symbol ? <SymbolMark symbol={symbol} size={28} /> : <Message01Icon width={20} height={20} aria-hidden="true" />,
          title: meaningOf(call),
          // The post is untrusted Discord text: rendered as text, never as HTML.
          subtitle: said ? `“${said}”` : "A picture",
          time: untilText(endOfTradingDay(call.source.source_at), now),
          detail: <CallDetail call={call} accountId={accountId} said={said} now={now} />,
        }
      }}
    />
  )
}

/** What a waiting call says, what it means and why it waits, when it was posted and until when it can be answered. */
function CallDetail({ call, accountId, said, now }: { call: WaitingCall; accountId: string; said: string; now: Date }) {
  const picture = pictureOf(call.source)
  const gain = callGain(call)
  const why = whyWaits(call, accountId)
  return (
    <div className={styles.callDetail}>
      {picture && !said ? <PostPicture attachment={picture} /> : <p className={styles.callPost}>{said ? `“${said}”` : "A picture"}</p>}
      <div className={styles.callFact}>
        <h3 className={styles.callLabel}>What it means</h3>
        <p className={styles.callMeaning}>
          <span>{meaningOf(call)}</span>
          {gain && <Badge tone={gain.change < 0 ? "danger" : "success"}>{gain.line}</Badge>}
        </p>
        {why && <ReasoningBlock status="done" variant="plain" title={why.headline} reasoning={why.note ? [{ text: why.note }] : []} model={{ name: "Why it waits", mark: <Clock01Icon width={16} height={16} /> }} />}
      </div>
      <p className={styles.callWhen}>
        Posted {dateTime(call.source.source_at)}. {untilText(endOfTradingDay(call.source.source_at), now)}.
      </p>
    </div>
  )
}
