import type {
  AccountControlCommand,
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

export function startText(configuration: TradingConfiguration): string {
  const ids = [...new Set(configuration.routes.flatMap((r) => r.connections.map((c) => c.account_id)))]
  const accounts = ids.map((id) => `${id} (${configuration.accounts.find((a) => a.id === id)?.environment ?? "unknown"})`)
  const live = configuration.accounts.some((a) => ids.includes(a.id) && a.environment === "live")
  const gurus = [...new Set(configuration.routes.map((r) => configuration.profiles.find((p) => p.guru_id === r.guru_id)?.display_name ?? r.guru_id))]
  return `Start copying ${gurus.join(", ")} into ${accounts.join(", ")}?\n\n${live ? "This places real orders with real money." : "This places paper orders."}`
}

export const PAUSE_TEXT = "Pause copying? No new posts are copied until you start again."

export function controlText(command: AccountControlCommand): string {
  return command.action === "pause"
    ? `Pause copying into ${command.account_id}? New posts are not copied into it until you resume it.`
    : `Resume copying into ${command.account_id}?`
}

export const deleteRecordText = (accountId: string) =>
  `Delete the record of ${accountId}? Its shares stay at Alpaca; only this app's record of them goes.`

export function restoreText(candidate: PendingRestoreCandidate | null, candidateId: string): string {
  if (!candidate || candidate.candidate_id !== candidateId) throw new Refusal("The engine has no restore waiting under that id.")
  const accounts = candidate.account_ids.length ? candidate.account_ids.join(", ") : "no accounts"
  return `Replace this Mac's CopyTrading records with the backup (${accounts})?`
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
