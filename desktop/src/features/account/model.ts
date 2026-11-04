import type { AccountOverview, SourceActivity } from "../../../shared/contract"
import { monthDay } from "@/lib/format"
import { BADGE, cardOutcome } from "@/features/activity/outcome"

/** The badge tones the page uses for what became of a post: Activity's, so a post reads the same on both screens. */
export type OutcomeTone = (typeof BADGE)[keyof typeof BADGE]

export interface PostOutcome {
  label: string
  tone: OutcomeTone
  /** One line on what the post meant for this account; empty when the badge already says it. */
  read: string
}

/**
 * What a guru post did for one account, in Activity's own words: its title and tone, and for this account what it
 * did (the reason in `lib/reasons` wording when the call was not carried out).
 */
export function postOutcome(post: SourceActivity, accountId: string, now: Date): PostOutcome {
  const card = cardOutcome(post, now)
  const [first, ...rest] = card.accounts.find((a) => a.id === accountId)?.results ?? []
  const said = first ? (first.note ?? first.headline) : ""
  return { label: card.title, tone: BADGE[card.tone], read: rest.length > 0 ? `${said} and ${rest.length} more` : said }
}

/** Positions worth a row: the broker keeps fractions of a cent after a sale. */
export const heldPositions = (account: AccountOverview) =>
  account.positions.filter((p) => Number(p.market_value ?? 0) >= 0.01)

/** "Bought Oct 22": when the post that opened the holding was made. */
export function holdingNote(position: AccountOverview["positions"][number]): string | null {
  const postedAt = position.lots[0]?.posted_at
  return postedAt ? `Bought ${monthDay(postedAt)}` : null
}

/** Day change as a fraction of yesterday's close. */
export function dayChange(account: AccountOverview): { amount: number; fraction: number } | null {
  const b = account.balance
  if (!b) return null
  const amount = Number(b.day_change_usd)
  const close = Number(b.previous_close_equity)
  return { amount, fraction: close > 0 ? amount / close : 0 }
}
