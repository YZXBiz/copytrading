import type { SourceActivity, TradingConfiguration } from "../../../shared/contract"
import { type GuruAccountOutcome, guruAccountOutcomes } from "@/features/gurus/model"
import { type Bucket, bucketOf } from "./post-bucket"
import { type Tone, cardOutcome } from "./outcome"
import { quoteOf, readAsLine } from "./reading"

/** One row of the post table: the post with everything its columns say, worked out once. */
export interface ActivityRow {
  post: SourceActivity
  bucket: Bucket | null
  guru: string
  /** Their words in quotes, or what came instead of words. */
  said: string
  /** The first stock the post names, for its logo. */
  symbol: string | null
  /** What the post means, in one line. */
  meaning: string
  label: string
  tone: Tone
  /** What each account did, for the accounts chosen. */
  accounts: GuruAccountOutcome[]
}

export function activityRows(posts: SourceActivity[], now: Date, nameOf: (id: string | null) => string, accountId: string | null): ActivityRow[] {
  return posts.map((post) => {
    const outcome = cardOutcome(post, now)
    return {
      post,
      bucket: bucketOf(post, now),
      guru: nameOf(post.guru_id),
      said: quoteOf(post),
      symbol: post.instructions[0]?.symbol ?? null,
      meaning: readAsLine(post),
      label: outcome.title,
      tone: outcome.tone,
      accounts: guruAccountOutcomes(post, now).filter((a) => accountId === null || a.accountId === accountId),
    }
  })
}

/** Whether a row's words match a search: its guru, words, meaning, status, stock and what its accounts did. */
export function matches(row: ActivityRow, query: string): boolean {
  const needle = query.trim().toLowerCase()
  if (needle === "") return true
  return [row.guru, row.said, row.meaning, row.label, ...row.post.instructions.map((i) => i.symbol), ...row.accounts.flatMap((a) => [a.accountId, a.summary])].join(" ").toLowerCase().includes(needle)
}

/**
 * The posts of the channels the saved setup follows. The engine keeps every post it ever captured, so posts
 * from channels the setup no longer copies (old test runs) would otherwise count as this setup's activity.
 * With no saved setup there is nothing to follow, and every post is shown.
 */
export function followedPosts(posts: SourceActivity[], config: TradingConfiguration | null): SourceActivity[] {
  if (!config) return posts
  const followed = new Set(config.routes.map((r) => `${r.source}:${r.channel_id}`))
  return posts.filter((p) => followed.has(p.source_id?.split(":").slice(0, 2).join(":") ?? ""))
}
