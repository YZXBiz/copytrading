import type { AgentProposal } from "../../../shared/contract"
import { isAssistant, summary } from "../../../shared/proposal-words"
import type { Fill } from "./watch"

// The words of each macOS notification, as FillNotifications.swift, AgentRequestNotifications.swift,
// CopyingStoppedNotification.swift and AccountStoppedText.swift say them.

export interface Note {
  /** The same id replaces the note it names; a different one adds another. */
  id: string
  title: string
  body: string
  /** Notes with one thread group together. */
  thread: string
  /** Where clicking it opens the window, as a route hash. */
  route?: string
  /** An order that filled: the open window shows it as a toast. */
  fill?: boolean
}

const isCoin = (symbol: string) => symbol.includes("/")
const isOne = (n: number) => Math.abs(n - 1) < 0.01

const group = (n: number, digits: number) => n.toLocaleString("en-US", { minimumFractionDigits: 0, maximumFractionDigits: digits })

/** Humanize.sharesOf: "2.985 shares", "1 share", "≈1 share" for a rounded count, or a coin's count alone. */
export function sharesOf(value: string, symbol: string): string {
  const n = Number(value)
  if (isCoin(symbol)) return group(n, 9)
  const whole = Math.round(n)
  const shown = Math.abs(n - whole) >= 0.01 ? Math.round(n * 1000) / 1000 : whole
  const text = `${shown === n ? "" : "≈"}${group(shown, 3)}`
  return `${text} ${isOne(n) ? "share" : "shares"}`
}

const usd = (value: string) => Number(value).toLocaleString("en-US", { style: "currency", currency: "USD" })

/** "Buying 9.804 shares of GFS at up to $51.00": an order that just went to the broker. */
function sentTitle(fill: Fill): string {
  const [shares, stock, sell] = [sharesOf(fill.shares, fill.symbol), fill.symbol, fill.side === "sell"]
  if (fill.price === null) return `${sell ? "Selling" : "Buying"} ${shares} of ${stock}`
  return sell ? `Selling ${shares} of ${stock} at ${usd(fill.price)} or more` : `Buying ${shares} of ${stock} at up to ${usd(fill.price)}`
}

/** "Bought 9.804 shares of GFS at $48.49": an order that filled. */
function filledTitle(fill: Fill): string {
  const [shares, stock, sell] = [sharesOf(fill.shares, fill.symbol), fill.symbol, fill.side === "sell"]
  if (fill.price === null) return `${sell ? "Sold" : "Bought"} ${shares} of ${stock}`
  return `${sell ? "Sold" : "Bought"} ${shares} of ${stock} at ${usd(fill.price)}`
}

/** "From Zhao's post · paper", "Your sale · paper", or "Into paper". */
export function origin(fill: Fill, guruName: (id: string) => string | null): string {
  if (fill.byOwner) return `Your sale · ${fill.accountId}`
  const name = fill.guruId ? guruName(fill.guruId) : null
  return name ? `From ${name}'s post · ${fill.accountId}` : `Into ${fill.accountId}`
}

export function fillNotes(news: { sent: Fill[]; filled: Fill[] }, guruName: (id: string) => string | null): Note[] {
  const note = (fill: Fill, kind: "sent" | "fill", title: string): Note => ({
    id: `${kind}-${fill.clientId}`,
    title,
    body: origin(fill, guruName),
    thread: fill.accountId,
    route: `#/accounts/${encodeURIComponent(fill.accountId)}`,
    ...(kind === "fill" && { fill: true }),
  })
  return [...news.sent.map((f) => note(f, "sent", sentTitle(f))), ...news.filled.map((f) => note(f, "fill", filledTitle(f)))]
}

/** An agent's request is waiting. The assistant's own are not announced: the owner is already looking. */
export function agentRequestNote(proposal: AgentProposal): Note | null {
  if (isAssistant(proposal.requested_by.path)) return null
  return { id: `agent-${proposal.proposal_id}`, title: "An agent is asking for approval", body: summary(proposal), thread: "agent-requests", route: "#/settings/agents" }
}

export const copyingPausedNote = (): Note => ({
  id: "copying-stopped",
  title: "Copying is paused",
  body: "Copying paused when CopyTrading quit. Open CopyTrading and press Start Copying.",
  thread: "copying-stopped",
})

export const accountStoppedNote = (accountId: string, unique: string): Note => ({
  id: `stopped-${accountId}-${unique}`,
  title: `Copying into ${accountId} stopped`,
  body: "CopyTrading hit a problem it couldn't fix. Stop copying everywhere, then start again to reopen it.",
  thread: "account-stopped",
  route: `#/accounts/${encodeURIComponent(accountId)}`,
})
