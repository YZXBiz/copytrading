import type { CatchUpItem } from "@/components/arc/blocks/catch-up/catch-up-data"
import type { SourceActivity } from "../../../shared/contract"
import { waitingCall } from "@/features/account/waiting"
import { dateTime, timeOfDay } from "@/lib/format"
import { getTimeZone } from "@/lib/time-zone"
import { cancelReason, isOwnerSale, orderOutcome, shownOrders } from "./outcome"
import { bucketOf, dayKey, skipReasonsOf } from "./post-bucket"
import { headline } from "./reading"

// What happened to the posts that came in since the owner last looked, in the words the rest of Activity uses for each order.

export interface CatchUpSummary {
  items: CatchUpItem[]
  /** The line under the card's title: the counts, then since when. */
  summary: string
}

/** The posts that arrived after `since`, sorted into what waits for the owner, what was copied (and how much of it filled) and what was skipped and why. Null when none did. `accountId` keeps one account's. */
export function catchUp(posts: SourceActivity[], since: Date, now: Date, nameOf: (id: string | null) => string, accountId: string | null = null): CatchUpSummary | null {
  const items: CatchUpItem[] = []
  const count = { copied: 0, filled: 0, waiting: 0, skipped: 0 }
  for (const post of posts) {
    if (Date.parse(post.source_at) <= since.getTime()) continue
    const bucket = bucketOf(post, now)
    const at = { when: timeOfDay(post.source_at), people: [{ name: nameOf(post.guru_id) }] }
    const mine = post.destinations.filter((d) => accountId === null || d.account_id === accountId)
    if (bucket === "waiting") {
      const accounts = (waitingCall(post)?.accountIds ?? []).filter((id) => accountId === null || id === accountId)
      if (accounts.length === 0) continue
      count.waiting++
      items.push({ id: `${post.sequence}:waiting`, section: "needs-you", text: headline(post), context: accountId === null ? accounts.join(", ") : undefined, ...at })
    } else if (bucket === "traded" || (bucket === "skipped" && mine.length > 0)) {
      // An order that went out is copied, whether or not it filled; one that was cancelled or refused is a skip, with the reason the order card gives.
      let ordered = false
      for (const d of mine) {
        for (const order of shownOrders(d).filter((o) => !isOwnerSale(o))) {
          ordered = true
          const outcome = orderOutcome(order)
          const context = accountId === null ? d.account_id : undefined
          if (["filled", "partly", "working", "stop"].includes(outcome.kind)) {
            count.copied++
            if (outcome.kind === "filled") count.filled++
            items.push({ id: `${post.sequence}:${order.client_id}`, section: "copied", text: outcome.detail, context, ...at })
          } else {
            count.skipped++
            items.push({ id: `${post.sequence}:${order.client_id}`, section: "skipped", text: outcome.kind === "cancelled" ? `${outcome.detail}: ${cancelReason(order)}` : outcome.detail, context, ...at })
          }
        }
      }
      if (!ordered && bucket === "skipped") {
        count.skipped++
        items.push({ id: `${post.sequence}:skipped`, section: "skipped", text: `${headline(post)}. ${skipReasonsOf(post, accountId).join(". ")}`, ...at })
      }
    }
  }
  if (items.length === 0) return null
  const parts = [
    count.copied && `${count.copied} copied`,
    count.filled && `${count.filled} filled`,
    count.waiting && `${count.waiting} waiting for you`,
    count.skipped && `${count.skipped} skipped`,
  ].filter(Boolean)
  const sameDay = dayKey(since, getTimeZone()) === dayKey(now, getTimeZone())
  return { items, summary: `${parts.join(", ")} since ${sameDay ? timeOfDay(since.toISOString()) : dateTime(since.toISOString())}` }
}
