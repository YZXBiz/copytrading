import { Badge } from "@/components/reui/badge"
import { Frame, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { Button } from "@/components/ui/button"
import { Item, ItemActions, ItemContent, ItemDescription, ItemGroup, ItemTitle } from "@/components/ui/item"
import { endOfTradingDay, untilText } from "@/features/activity/deadline"
import { namedBuyNote } from "@/features/activity/outcome"
import { PostPicture } from "@/features/activity/PostPicture"
import { pictureOf, readableText } from "@/features/activity/reading"
import { type WaitingCall, callPhrase, gainLine } from "./waiting"
import type { Recent } from "./skipped-calls"

/** The button's word: enter the trade yourself, approve what the account held, or copy what the post called. */
const copyLabel = (call: WaitingCall) => (call.calls.length === 0 ? "Enter Trade…" : call.awaitsApproval ? "Approve…" : "Copy…")

/**
 * One waiting call, as a row (Kraken's pending transactions, Revolut's pending orders): what copying places, the guru's
 * own words as one quoted line (or their picture when they wrote none), until when it can be copied, and the two
 * answers. Pressing the row opens the review, as Copy does.
 */
function CallRow({ call, canCopy, now, onCopy, onSkip }: { call: WaitingCall; canCopy: boolean; now: Date; onCopy: () => void; onSkip: () => void }) {
  const first = call.calls[0]
  const title = first ? callPhrase(first) + (call.calls.length > 1 ? ` and ${call.calls.length - 1} more` : "") : "Enter the trade yourself"
  const held = namedBuyNote(call.source)
  const gain = first ? gainLine(first) : null
  // The post is untrusted Discord text: rendered as text, never as HTML. A relay's bare label is not words, so the picture shows instead.
  const said = readableText(call.source)
  const picture = pictureOf(call.source)
  return (
    <Item size="xs" aria-label="Call waiting for you" onClick={canCopy ? onCopy : undefined} className={canCopy ? "hover:bg-muted/50 cursor-pointer" : undefined}>
      <ItemContent className="min-w-0 basis-64 gap-0.5">
        <ItemTitle className="w-full">
          <span className="truncate">{title}</span>
          {/* A sell held for its buy price has no buy to gain on: it says what came of that buy. */}
          {held ? (
            <span className="text-muted-foreground shrink-0 text-xs font-normal">{held}</span>
          ) : (
            gain && <Badge variant={gain.change < 0 ? "destructive-light" : "success-light"}>{gain.line}</Badge>
          )}
        </ItemTitle>
        {said && <ItemDescription className="line-clamp-1 break-words">“{said}”</ItemDescription>}
        {picture && <PostPicture attachment={picture} className="max-h-10" />}
      </ItemContent>
      <span className="text-muted-foreground shrink-0 text-xs tabular-nums">{untilText(endOfTradingDay(call.source.source_at), now)}</span>
      <ItemActions onClick={(event) => event.stopPropagation()}>
        <Button type="button" size="xs" variant="ghost" onClick={onSkip}>
          Skip
        </Button>
        <Button type="button" size="xs" disabled={!canCopy} onClick={onCopy} title={canCopy ? undefined : "Copying is off, so nothing can be placed yet."}>
          {copyLabel(call)}
        </Button>
      </ItemActions>
    </Item>
  )
}

/** The calls this account holds for the owner, newest first, until its trading day ends. Nothing shows when nothing waits. */
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
      {calls.length > 0 && (
        <Frame spacing="default">
          <FrameHeader className="flex-row items-center gap-2">
            <FrameTitle>Waiting for you</FrameTitle>
            <Badge variant="warning-light">{calls.length}</Badge>
          </FrameHeader>
          <FramePanel>
            <ItemGroup className="gap-0.5">
              {calls.map((call) => (
                <CallRow key={call.source.sequence} call={call} canCopy={canCopy} now={now} onCopy={() => onCopy(call)} onSkip={() => onSkip(call)} />
              ))}
            </ItemGroup>
          </FramePanel>
        </Frame>
      )}
      {recent && (
        <div className="text-muted-foreground flex items-baseline gap-3 py-1 text-sm">
          <span className="truncate">{recent.text ? `Skipped “${recent.text}”` : "Skipped"}</span>
          <Button type="button" size="xs" variant="ghost" onClick={onUndo}>
            Undo
          </Button>
        </div>
      )}
    </section>
  )
}
