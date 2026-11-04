import type {
  AccountControlCommand,
  AgentAccess,
  AccountPolicy,
  AgentProposal,
  LotSaleConfirmation,
  LotSalePreview,
  ManualConfirmation,
  ManualOrderPlan,
  ManualOrderPreview,
  PendingRestoreCandidate,
  TradingConfiguration,
} from "../../shared/contract"

// The words of every confirmation dialog. They come from what the engine told main (a preview it
// planned, the proposal it holds, the saved setup), never from text the renderer sends, so the
// dialog says what will happen even if the page asking is wrong about it.

/** A request main will not send: the message goes back to the page as the error. */
export class Refusal extends Error {}

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`

export function orderText(plan: ManualOrderPlan | null, account: string): string {
  if (!plan) throw new Refusal("The engine planned no order for this preview.")
  const sell = plan.side === "sell"
  const price = plan.limit_price ? `at $${plan.limit_price} or better` : "at the market price"
  return `${sell ? "Sell" : "Buy"} ${plan.qty} ${plan.symbol} ${price} ${sell ? "from" : "in"} ${account}`
}

function seenPreview<T extends { request: { account_id: string } }>(seen: Map<string, unknown>, id: string, account: string): T {
  const preview = seen.get(id) as T | undefined
  if (!preview) throw new Refusal("This order was not previewed in this session. Preview it again.")
  if (preview.request.account_id !== account) throw new Refusal("This preview belongs to a different account.")
  return preview
}

export function lotSaleText(sale: LotSaleConfirmation, seen: Map<string, unknown>): string {
  const preview = seenPreview<LotSalePreview>(seen, sale.preview_id, sale.account_id)
  return `${orderText(preview.plan, sale.account_id)}?`
}

export function manualOrdersText(commands: ManualConfirmation[], seen: Map<string, unknown>): string {
  const lines = commands.map((c) => orderText(seenPreview<ManualOrderPreview>(seen, c.preview_id, c.account_id).plan, c.account_id))
  return commands.length === 1 ? `${lines[0]}?` : `Place ${plural(lines.length, "order")}?\n\n${lines.join("\n")}`
}

const joinAnd = (items: string[]) => (items.length < 2 ? items.join("") : `${items.slice(0, -1).join(", ")} and ${items.at(-1)}`)

/** One line per route, so a guru is never named against an account it does not copy into. */
function routeLines(configuration: TradingConfiguration): { lines: string[]; live: boolean } {
  const environment = (id: string) => configuration.accounts.find((a) => a.id === id)?.environment ?? "unknown"
  const lines = configuration.routes.map((route) => {
    const guru = configuration.profiles.find((p) => p.guru_id === route.guru_id && p.profile_revision === route.profile_revision)
    return `${guru?.display_name ?? route.guru_id} into ${joinAnd(route.connections.map((c) => `${c.account_id} (${environment(c.account_id)})`))}`
  })
  return { lines, live: configuration.routes.some((r) => r.connections.some((c) => environment(c.account_id) === "live")) }
}

export function startText(configuration: TradingConfiguration): string {
  const { lines, live } = routeLines(configuration)
  return `Start copying?\n\n${lines.join("\n")}\n\n${live ? "This places real orders with real money." : "This places paper orders."}`
}

/** Applying an edited setup while copying: what will copy where, which limits change, and what happens to copying meanwhile. */
export function applyText(saved: TradingConfiguration, requested: TradingConfiguration): string {
  const { lines, live } = routeLines(requested)
  const changes = limitLines(saved, requested)
  return [
    "Apply changes?",
    lines.join("\n"),
    ...(changes.length ? [changes.join("\n")] : []),
    "Copying pauses for a few seconds, checks every connection, and starts with the new setup. A post sent meanwhile is still copied. If a check fails, your saved setup starts again.",
    live ? "This places real orders with real money." : "This places paper orders.",
  ].join("\n\n")
}

type Show = (value: string | number | boolean) => string
const USD: Show = (v) => `$${v}`
const PCT: Show = (v) => `${v}%`
const FLAG: Show = (v) => (v ? "on" : "off")
const SECONDS: Show = (v) => `${v} seconds`
// How the owner reads each account limit, as Settings words it, and how its value is written.
// A limit missing here still shows, under its own name, so no change goes unnamed.
const LIMITS: Partial<Record<keyof AccountPolicy, [label: string, show: Show]>> = {
  max_order_usd: ["Each order", USD],
  max_symbol_usd: ["Each stock", USD],
  max_total_usd: ["Invested in total", USD],
  daily_loss_cap_usd: ["Loss per day", USD],
  max_entries_per_day: ["Buys per day", String],
  max_signal_age_seconds: ["Oldest post to copy", SECONDS],
  order_timeout_seconds: ["Order timeout", SECONDS],
  poll_seconds: ["Check for orders every", SECONDS],
  extended_hours: ["Extended hours", FLAG],
  overnight: ["Overnight", FLAG],
  copy_exits: ["Copy sells", FLAG],
  approve_orders: ["Approve each order", FLAG],
  max_above_signal_pct: ["Buy above the guru's price by up to", PCT],
  max_below_signal_pct: ["Sell below the guru's price by up to", PCT],
  recovery_preference: ["After a restart", (v) => (v === "automatic" ? "resume by itself" : "wait for you")],
}

/** What changing the saved limits to the requested ones does, account by account. */
function limitLines(saved: TradingConfiguration, requested: TradingConfiguration): string[] {
  return requested.accounts.flatMap((account) => {
    const before = saved.accounts.find((a) => a.id === account.id)?.policy
    if (!before) return []
    const keys = new Set([...Object.keys(before), ...Object.keys(account.policy)]) as Set<keyof AccountPolicy>
    const changes = [...keys]
      .filter((key) => before[key] !== account.policy[key])
      .map((key) => {
        const [label, show] = LIMITS[key] ?? [key, String]
        return `${label} ${show(before[key])} → ${show(account.policy[key])}`
      })
    return changes.length ? [`${account.id}: ${changes.join("; ")}`] : []
  })
}

export function limitsText(saved: TradingConfiguration, requested: TradingConfiguration): string {
  const lines = limitLines(saved, requested)
  if (!lines.length) throw new Refusal("No limit is different from the saved one.")
  return `Change copying limits now?\n\n${lines.join("\n")}\n\nCopying uses them from the next post.`
}

export const PAUSE_TEXT = "Pause copying? No new posts are copied until you start again."

export function controlText(command: AccountControlCommand): string {
  return command.action === "pause"
    ? `Pause copying into ${command.account_id}? New posts are not copied into it until you resume it.`
    : `Resume copying into ${command.account_id}?`
}

export const deleteRecordText = (accountId: string) =>
  `Delete the record of ${accountId}? Its shares stay at Alpaca; only this app's record of them goes.`

const RESTORE_DETAIL = "Copying pauses while it restores. If anything doesn't match your broker's records, nothing is replaced."

/** A backup the owner previewed this session, or the half-finished restore the engine holds. */
export function restoreText(accountIds: string[]): string {
  return `Replace this Mac's CopyTrading records with the backup (${accountIds.length ? accountIds.join(", ") : "no accounts"})?\n\n${RESTORE_DETAIL}`
}

export function candidateText(candidate: PendingRestoreCandidate | null, candidateId: string): string {
  if (!candidate || candidate.candidate_id !== candidateId) throw new Refusal("The engine has no restore waiting under that id.")
  return restoreText(candidate.account_ids)
}

export const ROLLBACK_TEXT = "Undo the restore and go back to your records from before?\n\nCopying pauses while it does."

const ACCESS_TEXT: Record<AgentAccess, string> = {
  off: "Turn off agent access?\n\nPrograms such as the copytrading command and MCP server can no longer reach CopyTrading.",
  read_pause: "Allow agents to read and pause?\n\nPrograms such as the copytrading command and MCP server can read your accounts and pause copying. They cannot ask you to approve anything.",
  propose:
    "Allow agents to read, pause, and ask for approval?\n\nPrograms such as the copytrading command and MCP server can read your accounts, pause copying, and ask for things that could trade. Each one waits for your approval here.",
}

export function accessText(access: unknown): string {
  if (access !== "off" && access !== "read_pause" && access !== "propose") throw new Refusal("That is not a choice of agent access.")
  return ACCESS_TEXT[access]
}

export function proposalText(proposal: AgentProposal): string {
  if (proposal.state !== "pending") throw new Refusal(`This request is ${proposal.state.replace("_", " ")}.`)
  const s = proposal.subject
  switch (s.kind) {
    case "resume_account":
      return `Resume copying into ${s.account_id}?`
    case "set_recovery":
      return `After a restart, ${s.preference === "automatic" ? "resume copying into" : "wait for you before copying into"} ${s.account_id}?`
    case "confirm_manual_order": {
      const sell = s.side === "sell"
      const price = s.limit_price ? `at $${s.limit_price} or better` : "at the market price"
      return `${sell ? "Sell" : "Buy"} ${s.quantity} ${s.symbol} ${price} ${sell ? "from" : "in"} ${s.account_id}?`
    }
    case "set_account_limits":
      return `Change ${s.account_id}: ${s.changes.map((c) => `${c.field} to ${c.value}`).join(", ")}?`
    case "start_processing":
      return "Start copying the saved setup?"
    case "apply_setup":
      return "Check, save and start the setup an agent proposed? It touches live accounts."
  }
}
