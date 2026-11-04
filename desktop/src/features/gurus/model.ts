import type { AccountOverview, GuruDayStats, SourceActivity, TradingConfiguration, TradingEnvironment } from "../../../shared/contract"
import { num } from "../activity/amounts"
import { isOpenCall, orderOutcome, isOwnerSale, cardOutcome } from "../activity/outcome"
import { readAsLine } from "../activity/reading"
import { dayLabel } from "../activity/time"

// The gurus a saved setup copies, and what their pages show (GuruDirectory, GuruFeed, GuruStats, GuruHoldings).

export interface Guru {
  id: string
  name: string
  /** The accounts their calls go to, once each, with whether each is paper or live. */
  accounts: { id: string; environment: TradingEnvironment | null }[]
}

/** One entry per guru the setup routes, named by their profile and sorted by name. */
export function guruDirectory(config: TradingConfiguration | null | undefined): Guru[] {
  const byId = new Map<string, Guru>()
  for (const route of config?.routes ?? []) {
    const profile = config!.profiles.find((p) => p.profile_revision === route.profile_revision)
    const guru = byId.get(route.guru_id) ?? { id: route.guru_id, name: profile?.display_name ?? route.guru_id, accounts: [] }
    for (const { account_id } of route.connections) {
      if (!guru.accounts.some((a) => a.id === account_id)) {
        guru.accounts.push({ id: account_id, environment: config!.accounts.find((a) => a.id === account_id)?.environment ?? null })
      }
    }
    byId.set(route.guru_id, guru)
  }
  return [...byId.values()].sort((a, b) => a.name.localeCompare(b.name, "en", { numeric: true }))
}

export const guruName = (gurus: Guru[], id: string | null) => (id ? (gurus.find((g) => g.id === id)?.name ?? id) : "Unknown guru")

// ── What each account did with a guru's post, short enough for a feed row ──

export type OutcomeKind = "traded" | "notTraded" | "waiting" | "working" | "settled"

export interface GuruAccountOutcome {
  accountId: string
  /** "primary · Not bought: the price ran above your limit" is account and summary. */
  summary: string
  kind: OutcomeKind
}

const CARRIED_ON = ["order_linked", "pending", "waiting_for_quote", "approved_by_owner"]

export function guruAccountOutcomes(post: SourceActivity, now: Date): GuruAccountOutcome[] {
  const card = cardOutcome(post, now)
  return post.destinations.map((d, index) => {
    const account = card.accounts[index]!
    const [first, ...rest] = account.results
    const summary = rest.length > 0 ? `${first!.headline} and ${rest.length} more` : (first?.headline ?? "")
    const orders = (d.orders ?? []).filter((o) => !isOwnerSale(o)).map((o) => orderOutcome(o))
    let kind: OutcomeKind
    if (account.waits) kind = "waiting"
    else if (orders.some((o) => o.kind === "filled" || o.kind === "partly")) kind = "traded"
    else if (orders.some((o) => o.kind === "working" || o.kind === "review")) kind = "working"
    else if (orders.length > 0 || d.instruction_outcomes.some((o) => !CARRIED_ON.includes(o)) || ["stale", "out_of_order", "ignored"].includes(d.status)) kind = "notTraded"
    else kind = "settled"
    return { accountId: d.account_id, summary, kind }
  })
}

// ── The timeline ──

export interface Entry {
  post: SourceActivity
  readAs: string
  accounts: GuruAccountOutcome[]
  /** A call of the post still waits for the owner, and its trading day is not over. */
  isWaiting: boolean
}

export interface Day {
  label: string
  entries: Entry[]
}

export interface Feed {
  days: Day[]
  waitingCount: number
}

/**
 * One guru's posts, newest first, grouped by day. `day` is the engine's count for the guru: the posts it holds
 * as waiting are listed whether or not they are among the pages loaded, and they are the only ones that read as waiting.
 */
export function buildFeed(guruId: string, loaded: SourceActivity[], day: GuruDayStats | undefined, now: Date): Feed {
  const waiting = (day?.waiting ?? []).filter((p) => isOpenCall(p, now))
  const waitingIds = new Set(waiting.map((p) => p.sequence))
  const posts = [...waiting, ...loaded.filter((p) => !waitingIds.has(p.sequence))]
    .filter((p) => p.guru_id === guruId)
    .sort((a, b) => Date.parse(b.source_at) - Date.parse(a.source_at) || b.sequence - a.sequence)
  const days: Day[] = []
  for (const post of posts) {
    const entry: Entry = { post, readAs: readAsLine(post), accounts: guruAccountOutcomes(post, now), isWaiting: waitingIds.has(post.sequence) }
    const label = dayLabel(post.source_at, now)
    const last = days[days.length - 1]
    if (last && last.label === label) last.entries.push(entry)
    else days.push({ label, entries: [entry] })
  }
  return { days, waitingCount: posts.filter((p) => waitingIds.has(p.sequence)).length }
}

export type PostFilter = "all" | "traded" | "waiting" | "notTraded"

export const POST_FILTERS: { id: PostFilter; label: string }[] = [
  { id: "all", label: "All" },
  { id: "traded", label: "Traded" },
  { id: "waiting", label: "Waiting" },
  { id: "notTraded", label: "Not traded" },
]

export function includesEntry(filter: PostFilter, entry: Entry): boolean {
  const kinds = entry.accounts.map((a) => a.kind)
  switch (filter) {
    case "all": return true
    case "traded": return kinds.includes("traded")
    case "waiting": return entry.isWaiting
    case "notTraded": return !kinds.includes("traded") && !entry.isWaiting && !kinds.includes("working")
  }
}

// ── Today's numbers and what is held ──

export interface Stats {
  /** Null until the engine's counts for the day are read: before that a zero would be a guess. */
  postsToday: number | null
  tradedToday: number | null
  waiting: number
  /** How long the reader took per post today, on average. */
  averageRead: number | null
}

export const guruStats = (day: GuruDayStats | undefined, waiting: number, isRead: boolean): Stats => ({
  postsToday: isRead ? (day?.posts ?? 0) : null,
  tradedToday: isRead ? (day?.traded ?? 0) : null,
  waiting,
  averageRead: day?.read_seconds ?? null,
})

export interface Holdings {
  cost: number
  gain: number
  stocks: number
}

/** What the owner holds from one guru's calls, in the accounts the setup copies into; none while nothing is held. */
export function guruHoldings(guruId: string, accounts: AccountOverview[], setUpIds: Set<string>): Holdings | null {
  const lots = accounts
    .filter((a) => setUpIds.has(a.account_id))
    .flatMap((a) => a.positions.flatMap((p) => p.lots.filter((l) => l.guru_id === guruId && (num(l.remaining_qty) ?? 0) > 0).map((lot) => ({ lot, symbol: p.symbol }))))
  if (lots.length === 0) return null
  return {
    cost: lots.reduce((sum, { lot }) => sum + (num(lot.remaining_qty) ?? 0) * (num(lot.average_price) ?? 0), 0),
    gain: lots.reduce((sum, { lot }) => sum + (num(lot.unrealized_pl) ?? 0), 0),
    stocks: new Set(lots.map((l) => l.symbol)).size,
  }
}
