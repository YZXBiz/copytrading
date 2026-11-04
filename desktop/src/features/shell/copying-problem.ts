import type { TradingStatus } from "../../../shared/contract"
import { joinAnd } from "../../../shared/start-failure"
import { reasonText, sentence } from "@/lib/reasons"

/**
 * What is wrong while the engine says copying runs "with problems" (degraded): the account, what happened, what to do.
 * The engine marks it degraded when an account stopped, Discord is not connected, the model service is not answering,
 * or alerts cannot be sent; the first of those that holds is named, because it is the one that stops posts being copied.
 */
export function copyingProblem(status: TradingStatus): string {
  const failed = (status.accounts ?? []).filter((account) => account.state === "failed")
  if (failed.length > 0) {
    const reasons = new Set(failed.map((account) => account.error_code ?? "account_unavailable"))
    const names = joinAnd(failed.map((account) => account.id))
    const why = reasons.size === 1 ? sentence(reasonText([...reasons][0])) : "They stopped for different reasons."
    return `${names} stopped copying. ${why} Open Accounts to see what to do.`
  }
  if (!status.source_connected) {
    if (status.error_code === "source_unauthorized") return "Discord didn't accept your token, so posts aren't being read. Paste a new one in Connections."
    if (status.error_code) return "Discord can't be reached, so new posts aren't being read. CopyTrading keeps trying; check your internet connection."
    return "Still connecting to Discord, so new posts aren't being read yet."
  }
  if (!status.model_ready) return "The model service isn't answering, so posts aren't being read. Check its API key and your internet connection in Connections."
  if (status.error_code === "notification_unavailable") return "Alerts aren't reaching your notification channel. Check it in Connections."
  return "The engine reports a problem but named no cause. If it stays, pause copying and start it again."
}
