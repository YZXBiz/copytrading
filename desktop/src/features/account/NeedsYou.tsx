// ReUI's Integrations list (list-8), installed as shipped and wired to the calls waiting for the owner: a row per
// call with its tile, title and one description line, and the buttons on the right. Pressing a row opens the review.
import { CheckIcon, PencilLineIcon } from "lucide-react"
import { EmptyState } from "@/components/empty-state"
import { navigate } from "@/features/shell/route"
import { Badge } from "@/components/reui/badge"
import { Frame, FramePanel } from "@/components/reui/frame"
import { IconTile } from "@/components/reui/icon-tile"
import { SymbolLogo } from "@/components/symbol-logo"
import { Button } from "@/components/ui/button"
import { Separator } from "@/components/ui/separator"
import { endOfTradingDay, untilText } from "@/features/activity/deadline"
import { namedBuyNote } from "@/features/activity/outcome"
import { PostPicture } from "@/features/activity/PostPicture"
import { pictureOf, readableText } from "@/features/activity/reading"
import { type WaitingCall, callPhrase, gainLine } from "./waiting"
import type { Recent } from "./skipped-calls"

/** The button's word: enter the trade yourself, approve what the account held, or copy what the post called. */
const copyLabel = (call: WaitingCall) => (call.calls.length === 0 ? "Enter Trade…" : call.awaitsApproval ? "Approve…" : "Copy…")

/** One waiting call: what copying places, the guru's own words as one line (or their picture when they wrote none), until when it can be copied, and the two answers. */
function CallRow({ call, showSeparator, canCopy, now, onCopy, onSkip }: { call: WaitingCall; showSeparator: boolean; canCopy: boolean; now: Date; onCopy: () => void; onSkip: () => void }) {
  const first = call.calls[0]
  const title = first ? callPhrase(first) + (call.calls.length > 1 ? ` and ${call.calls.length - 1} more` : "") : "Enter the trade yourself"
  const held = namedBuyNote(call.source)
  const gain = first ? gainLine(first) : null
  // The post is untrusted Discord text: rendered as text, never as HTML. A relay's bare label is not words, so the picture shows instead.
  const said = readableText(call.source)
  const picture = pictureOf(call.source)
  return (
    <li aria-label="Call waiting for you">
      <div className={canCopy ? "flex cursor-pointer items-center gap-2" : "flex items-center gap-2"} onClick={canCopy ? onCopy : undefined}>
        {first ? (
          <SymbolLogo symbol={first.symbol} />
        ) : (
          <IconTile variant="frame" size="sm" aria-hidden="true">
            <PencilLineIcon />
          </IconTile>
        )}

        <div className="min-w-0 flex-1 space-y-0.5">
          <p className="text-foreground flex items-center gap-2 text-sm font-medium">
            <span className="truncate">{title}</span>
            {/* A sell held for its buy price has no buy to gain on: it says what came of that buy. */}
            {held ? (
              <span className="text-muted-foreground shrink-0 text-xs font-normal">{held}</span>
            ) : (
              gain && <Badge variant={gain.change < 0 ? "destructive-light" : "success-light"}>{gain.line}</Badge>
            )}
          </p>
          {said && <p className="text-muted-foreground line-clamp-1 text-xs break-words">“{said}”</p>}
          {picture && <PostPicture attachment={picture} className="max-h-10" />}
        </div>

        <span className="text-muted-foreground shrink-0 text-xs tabular-nums">{untilText(endOfTradingDay(call.source.source_at), now)}</span>
        <div className="flex shrink-0 items-center gap-2" onClick={(event) => event.stopPropagation()}>
          <Button type="button" variant="ghost" size="lg" onClick={onSkip}>
            Skip
          </Button>
          <Button type="button" variant="outline" size="lg" disabled={!canCopy} onClick={onCopy} title={canCopy ? undefined : "Copying is off, so nothing can be placed yet."}>
            {copyLabel(call)}
          </Button>
        </div>
      </div>
      {showSeparator ? <Separator className="my-3.5 w-auto border-t border-dashed bg-transparent" /> : null}
    </li>
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
  onSkipAll,
  onUndo,
}: {
  calls: WaitingCall[]
  canCopy: boolean
  now: Date
  recent: Recent | null
  onCopy: (call: WaitingCall) => void
  onSkip: (call: WaitingCall) => void
  onSkipAll: () => void
  onUndo: () => void
}) {
  return (
    <section aria-label="Calls waiting for you" className="flex flex-col gap-3">
      {calls.length === 0 && (
        <Frame stacked className="@container w-full">
          <FramePanel className="flex items-center gap-2 px-3.5! py-4!">
            <h2 className="text-foreground text-base font-medium">Waiting for you</h2>
          </FramePanel>
          <FramePanel className="p-5!">
            <EmptyState icon={CheckIcon} title="Nothing is waiting for you" action={{ label: "See Activity", onClick: () => navigate("activity") }} />
          </FramePanel>
        </Frame>
      )}
      {calls.length > 0 && (
        <Frame stacked className="@container w-full">
          <FramePanel className="flex items-center gap-2 px-3.5! py-4!">
            {/* Header */}
            <h2 className="text-foreground text-base font-medium">Waiting for you</h2>
            <Badge variant="warning-light">{calls.length}</Badge>
            {calls.length > 1 && (
              <Button type="button" variant="ghost" size="sm" className="ml-auto" onClick={onSkipAll}>
                Skip all
              </Button>
            )}
          </FramePanel>

          <FramePanel className="p-5!">
            {/* Content */}
            <ul className="flex flex-col">
              {calls.map((call, index) => (
                <CallRow
                  key={call.source.sequence}
                  call={call}
                  showSeparator={index < calls.length - 1}
                  canCopy={canCopy}
                  now={now}
                  onCopy={() => onCopy(call)}
                  onSkip={() => onSkip(call)}
                />
              ))}
            </ul>
          </FramePanel>
        </Frame>
      )}
      {recent && (
        <div className="text-muted-foreground flex items-baseline gap-3 py-1 text-sm">
          <span className="truncate">{recent.text ? `Skipped “${recent.text}”` : recent.sourceIds.length > 1 ? `Skipped ${recent.sourceIds.length} calls` : "Skipped"}</span>
          <Button type="button" size="xs" variant="ghost" onClick={onUndo}>
            Undo
          </Button>
        </div>
      )}
    </section>
  )
}
