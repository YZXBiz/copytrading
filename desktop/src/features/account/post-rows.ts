import type { SourceActivity } from "../../../shared/contract"
import { isOpenCall } from "@/features/activity/outcome"
import { type OutcomeTone, postOutcome } from "./model"
import { type WaitingCall, meaningOf } from "./waiting"

/** The filter the posts table offers; "other" posts (failed, needing review) show under All only. */
export type PostFilter = "all" | "waiting" | "traded" | "ignored"

export const POST_FILTERS: { value: PostFilter; label: string }[] = [
  { value: "all", label: "All" },
  { value: "waiting", label: "Waiting" },
  { value: "traded", label: "Traded" },
  { value: "ignored", label: "Ignored" },
]

export interface PostTableRow {
  post: SourceActivity
  /** The call this account holds for the owner, when the post is one. */
  call: WaitingCall | null
  label: string
  tone: OutcomeTone
  /** What the post means for this account in one line: the call it holds, what became of it, or nothing. */
  meaning: string
  filter: Exclude<PostFilter, "all"> | "other"
}

/** The id a skip is kept under: the post's source id, or its sequence. */
export const sourceKey = (post: SourceActivity) => post.source_id ?? String(post.sequence)

/**
 * One row per guru post, the calls waiting for the owner first and the rest in the order given (newest first).
 * A call the owner skipped still reads "Waiting for you" in Activity's card, so it is named here for what it is.
 */
export function postRows(posts: SourceActivity[], calls: WaitingCall[], accountId: string, now: Date, skipped: (sourceId: string) => boolean): PostTableRow[] {
  const waiting = new Map(calls.map((call) => [call.source.sequence, call]))
  const rows = posts.map((post): PostTableRow => {
    const call = waiting.get(post.sequence) ?? null
    const outcome = postOutcome(post, accountId, now)
    if (call) return { post, call, label: "Waiting", tone: "warning-light", meaning: meaningOf(call), filter: "waiting" }
    if (isOpenCall(post, now) && skipped(sourceKey(post))) return { post, call, label: "Skipped", tone: "outline", meaning: "You skipped it", filter: "ignored" }
    const filter = outcome.tone === "outline" ? "ignored" : post.decision === "trade" && (outcome.tone === "success-light" || outcome.tone === "info-light") ? "traded" : "other"
    // Chat, and a call still waiting for the owner, have nothing to add to their badge.
    const quiet = post.decision === "ignore" || outcome.tone === "warning-light"
    return { post, call, label: outcome.label, tone: outcome.tone, meaning: quiet ? "" : outcome.read, filter }
  })
  return [...rows.filter((row) => row.call), ...rows.filter((row) => !row.call)]
}
