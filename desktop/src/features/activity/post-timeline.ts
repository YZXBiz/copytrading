import type { AgentTimelineAgent, AgentTimelineHandoff, AgentTimelineSpan } from "@/components/arc/agent-timeline/agent-timeline"
import type { DestinationActivity, OrderActivity, SourceActivity } from "../../../shared/contract"
import { parseDec } from "@/features/account/decimal"
import { money } from "@/lib/format"
import { sharesText } from "@/lib/quantity"
import { reasonText } from "@/lib/reasons"
import { duration } from "./amounts"
import { cancelReason } from "./outcome"
import { headline } from "./reading"
import { clockTime } from "./time"

// One post's steps in order: the reader, then each account, on a shared line. The line is a row of equal slots, one per moment
// the post reached a step, because the steps are milliseconds apart and a stop can rest for hours: a true time axis would
// squeeze every step but the last into one edge. The real times are on each step's card.

type Step = NonNullable<DestinationActivity["timeline"]>[number]
type Kind = AgentTimelineSpan["kind"]
type Raw = { agent: string; kind: Kind; from: number; to: number; label: string; tool?: string; failed?: boolean }

/** A step that moves no time of its own: it only marks a moment the next step starts from. */
const MARKERS = new Set(["received", "held"])
const KINDS: Record<string, Kind> = {
  sized: "thinking",
  skipped: "thinking",
  failed: "thinking",
  sent: "tool",
  accepted: "tool",
  resumed: "waiting",
  partially_filled: "waiting",
  filled: "waiting",
  cancel_requested: "waiting",
  cancelled: "waiting",
  expired: "waiting",
  rejected: "waiting",
}
/** A slot a step takes when it happened in the very same instant as the one before it. */
const MIN_SLOT = 0.6

export interface PostTimeline {
  agents: AgentTimelineAgent[]
  spans: AgentTimelineSpan[]
  handoffs: AgentTimelineHandoff[]
  /** The line under the title. */
  summary: string[]
}

const ms = (iso: string) => Date.parse(iso)
const capitalize = (text: string) => text.charAt(0).toUpperCase() + text.slice(1)

/** What a step says it did, in the words the rest of the post's detail uses. */
function stepLabel(step: Step, orders: OrderActivity[], sized: Map<string, Step>): { label: string; failed?: boolean; tool?: string } {
  const order = orders.find((o) => o.client_id === step.client_id)
  const symbol = order?.symbol ?? ""
  const stop = order?.order_type === "stop"
  const quantity = parseDec(step.quantity)
  const amount = quantity === null ? "" : sharesText(quantity, symbol)
  const price = step.price ?? sized.get(step.client_id ?? "")?.price ?? order?.stop_price ?? null
  const at = price === null ? "" : ` at ${money(price)}`
  const why = order ? capitalize(cancelReason(order)) : "Cancelled"
  switch (step.step) {
    case "sized": return { label: stop ? `Prepared a stop${at}` : `Sized the order: ${amount || "shares"}${at}` }
    case "skipped": return { label: `Skipped: ${reasonText(step.reason)}` }
    case "failed": return { label: `Did not go through: ${reasonText(step.reason)}`, failed: true }
    case "resumed": return { label: "Waited for you to resume copying" }
    case "sent": return { label: "Sent to Alpaca", tool: "Alpaca" }
    case "accepted": return { label: stop ? `Stop placed${at}` : "Alpaca accepted the order", tool: "Alpaca" }
    case "partially_filled": return { label: `${stop ? "Stop partly filled" : "Partly filled"}: ${amount}${at}` }
    case "filled": return { label: `${stop ? "Stop filled" : "Filled"}: ${amount}${at}` }
    case "cancel_requested": return { label: `Cancel requested: ${why.toLowerCase()}` }
    case "cancelled": return { label: `Cancelled: ${why.toLowerCase()}` }
    case "expired": return { label: "Expired: the trading day ended" }
    case "rejected": return { label: "Rejected by Alpaca", failed: true }
    default: return { label: capitalize(step.step.replace(/_/g, " ")) }
  }
}

/** The steps of one account's timeline as spans: each runs from the step before it to its own moment. */
function accountSpans(destination: DestinationActivity): Raw[] {
  const steps = destination.timeline ?? []
  const orders = destination.orders ?? []
  const sized = new Map(steps.filter((s) => s.step === "sized" && s.client_id).map((s) => [s.client_id!, s]))
  const spans: Raw[] = []
  let before = steps[0] ? ms(steps[0].at) : 0
  for (const step of steps) {
    const at = ms(step.at)
    if (!MARKERS.has(step.step)) {
      const { label, failed, tool } = stepLabel(step, orders, sized)
      spans.push({ agent: destination.account_id, kind: KINDS[step.step] ?? "waiting", from: before, to: at, label, failed, tool })
    }
    before = at
  }
  return spans
}

/** The reader's two steps, then each account's, with the moment each account received the post as the hand-over. Null when no step is on record. */
export function postTimeline(post: SourceActivity, accountId: string | null = null): PostTimeline | null {
  const destinations = post.destinations.filter((d) => (accountId === null || d.account_id === accountId) && (d.timeline?.length ?? 0) > 0)
  const received = ms(post.captured_at ?? post.source_at)
  const [readStart, readEnd] = [post.read_started_at ? ms(post.read_started_at) : null, post.read_at ? ms(post.read_at) : null]
  const reader: Raw[] = []
  if (readStart !== null && readEnd !== null) {
    if (readStart > received) reader.push({ agent: "reader", kind: "waiting", from: received, to: readStart, label: "Received the post" })
    const call = post.reading && "summary" in post.reading && post.reading.summary ? post.reading.summary : headline(post)
    reader.push({ agent: "reader", kind: "thinking", from: readStart, to: readEnd, label: `Read as: ${call}` })
  }
  const accounts = destinations.map((d) => ({ destination: d, spans: accountSpans(d) })).filter((a) => a.spans.length > 0)
  if (accounts.length === 0) return null

  // One slot per distinct moment, in order; a row never overlaps itself, so a step in the same instant as the last takes a small slot after it.
  const moments = [...new Set([...reader, ...accounts.flatMap((a) => a.spans)].flatMap((s) => [s.from, s.to]))].sort((a, b) => a - b)
  const slot = new Map(moments.map((moment, index) => [moment, index]))
  const place = (rows: Raw[]) => {
    let cursor = 0
    return rows.map((raw): AgentTimelineSpan => {
      const start = Math.max(slot.get(raw.from)!, cursor)
      const end = Math.max(slot.get(raw.to)!, start + MIN_SLOT)
      cursor = end
      const gap = (raw.to - raw.from) / 1000
      const meta = `${clockTime(new Date(raw.to).toISOString())}${gap >= 1 ? `, ${duration(gap)} after the step before` : ""}`
      return { agentId: raw.agent, kind: raw.kind, start, end, label: raw.label, tool: raw.tool, status: raw.failed ? "failed" : "ok", meta }
    })
  }
  const readerSpans = place(reader)
  const accountPlaced = accounts.map((a) => place(a.spans))
  const agents: AgentTimelineAgent[] = [
    ...(readerSpans.length > 0 ? [{ id: "reader", name: "Reader", model: post.interpreted_by ?? undefined }] : []),
    ...accounts.map((a) => ({ id: a.destination.account_id, name: a.destination.account_id, model: a.destination.environment === "live" ? "Live" : "Paper" })),
  ]
  const handoffs: AgentTimelineHandoff[] = readerSpans.length > 0 ? accountPlaced.map((spans, i) => ({ from: "reader", to: accounts[i]!.destination.account_id, at: spans[0]!.start, label: "Handed the post over" })) : []
  const [first, last] = [Math.min(...moments), Math.max(...moments)]
  const named = accounts.length === 1 ? "1 account" : `${accounts.length} accounts`
  const times = first === last ? clockTime(new Date(first).toISOString()) : `${clockTime(new Date(first).toISOString())} to ${clockTime(new Date(last).toISOString())}`
  return { agents, spans: [...readerSpans, ...accountPlaced.flat()], handoffs, summary: [named, times] }
}
