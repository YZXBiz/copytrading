import type { TradingStatus } from "./contract"

// Why a start did not take, in the words StartFailure.swift uses. Main words the error when it rolls a start back.

/** "A, B and C". */
export const joinAnd = (items: string[]): string =>
  items.length < 2 ? items.join("") : `${items.slice(0, -1).join(", ")} and ${items.at(-1)}`

const SHARED = "alpaca_account_shared"

function accountFailure(name: string, code: string | null): string {
  switch (code) {
    case SHARED:
      return `${name} didn't open: another account in this setup uses keys for the same Alpaca account. Remove one of them, or give it the keys of another Alpaca account.`
    case "record_unreadable":
      return `${name} didn't open: its record on this Mac couldn't be read, so nothing was changed. Quit and reopen CopyTrading.`
    case "broker_keys_rejected":
      return `${name} didn't open: Alpaca didn't accept its API keys. Paste them again from your Alpaca dashboard.`
    case "broker_unreachable":
      return `${name} didn't open: Alpaca couldn't be reached. Check your internet connection, then start again.`
    case "account_in_use":
      return `${name} didn't open: another CopyTrading on this Mac is copying into it. Quit the other one, then start again.`
    case "outside_open_orders":
      return `${name} didn't open: it has orders open at Alpaca that CopyTrading didn't place. Cancel them at Alpaca, then start again.`
    case "broker_account_inactive":
      return `${name} didn't open: Alpaca hasn't activated this account yet. Finish its setup at Alpaca, then start again.`
    default:
      return `${name} didn't open, and CopyTrading couldn't tell why.`
  }
}

/** Why the engine's own code stopped a start, when it names no account. */
function serviceFailure(code: string | null, modelService: string): string {
  switch (code) {
    case "source_unauthorized":
      return "Discord didn't accept your token. Copy a new one from Discord and paste it in Connections."
    case "source_unavailable":
      return "Discord couldn't be reached. Check your internet connection, then start again."
    case "provider_unavailable":
      return `${modelService} couldn't be reached. Check your internet connection and its API key, then start again.`
    case "routing_change_pending":
      return "Posts from your last setup were still being read or sent. Wait a minute, then start again."
    case "account_ownership_pending":
      return "An account you removed still has an order or a copy under way. Wait for it to finish, then start again."
    case "accounts_unavailable":
      return "More than one account didn't open. Accounts shows why for each one."
    case "storage_unavailable":
      return "CopyTrading couldn't open its data on this Mac. Quit and reopen CopyTrading."
    case "routing_state_unavailable":
      return "CopyTrading couldn't read its saved gurus. Quit and reopen CopyTrading."
    case null:
    case "processing_unavailable":
    case "activation_journal_unavailable":
    case "account_unavailable":
      return "CopyTrading stopped while starting. Start again."
    default: {
      const spaced = code.replace(/[_-]/g, " ")
      return `${spaced.charAt(0).toUpperCase()}${spaced.slice(1)}. Start again.`
    }
  }
}

/**
 * Why copying didn't start, in a sentence or two for each thing that stopped it: accounts the engine couldn't open come
 * first, each by name; otherwise the engine's reason names the service. `modelService` names the interpreter ("DeepSeek").
 */
export function startFailure(errorCode: string | null, accounts: NonNullable<TradingStatus["accounts"]>, modelService: string): string {
  const failed = accounts.filter((a) => a.state === "failed")
  if (!failed.length) return serviceFailure(errorCode, modelService)
  const shared = failed.filter((a) => a.error_code === SHARED).map((a) => a.id)
  const rest = failed.filter((a) => a.error_code !== SHARED).map((a) => accountFailure(a.id, a.error_code))
  const sharing =
    shared.length > 1
      ? [`${joinAnd(shared)} use keys for the same Alpaca account. Each account needs its own Alpaca account: remove one, or give it the keys of another.`]
      : shared.map((name) => accountFailure(name, SHARED))
  return [...sharing, ...rest].join(" ")
}
