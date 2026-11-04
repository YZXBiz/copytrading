import type { CapabilityCheck, ProviderName } from "../../../shared/contract"
import { joinAnd } from "../../../shared/start-failure"
import { PROVIDER_TITLES, acceptsBaseUrl, providerShortTitle } from "../../../shared/providers"

// What a check or a start found, in the words ConnectionProblem.swift, StartFailure.swift and CapabilityCheckTitle.swift use.

/** "GFS, NVDA and WMT"; past four, the first three and how many more. */
export const stocks = (symbols: string[]): string =>
  symbols.length > 4 ? joinAnd([...symbols.slice(0, 3), `${symbols.length - 3} more`]) : joinAnd(symbols)

/** What the app says when the engine could not run a check at all. */
export const ENGINE_UNAVAILABLE = "check_engine_unavailable"

const isProvider = (name: string): name is ProviderName => name in PROVIDER_TITLES

/** What a failed check means, in one plain sentence that says what to do next. `modelName` is what was checked. */
export function connectionProblem(check: CapabilityCheck, modelName = ""): string {
  const provider = isProvider(check.adapter) ? check.adapter : null
  const service = provider ? providerShortTitle(provider) : check.adapter
  const account = check.subject ?? ""
  switch (check.reason_code) {
    case "source_channel_access_denied":
    case "source_history_permission_denied":
    case "source_channel_not_readable":
      return "Your Discord account can't read one of these channels. Check the channel IDs."
    case "source_probe_timed_out":
    case "source_history_probe_timed_out":
      return "Discord didn't answer in time. Check your connection and try again."
    case "source_identity_unavailable":
    case "source_auth_or_channel_access":
    case "source_history_read_failed":
      return "Discord didn't accept the token, or can't find a channel. Check both."
    case "model_key_rejected":
      return `${service} didn't accept the API key.`
    case "model_not_found":
      return `${service} has no model called “${modelName.trim()}”.`
    case "model_probe_rejected":
      return "The model answered, but couldn't read a test post. Try another model."
    case "model_unreachable":
      if (provider === "ollama") return `Nothing answered at that address. Check the Base URL and that ${service} is running.`
      if (provider && acceptsBaseUrl(provider)) return "Nothing answered at that address. Check the Base URL and that the server is running."
      return `${service} didn't answer. Check your connection and try again.`
    case "model_auth_or_probe_failed":
      return `Couldn't reach ${service}. Check the API key and your connection.`
    case "broker_account_not_tradeable":
      return "Alpaca says this account can't trade yet. Check it on Alpaca's site."
    case "broker_keys_are_paper":
      return "These are paper keys. Choose Paper, or enter this account's live keys."
    case "broker_keys_are_live":
      return "These are live keys, for real money. Choose Live, or enter paper keys."
    case "broker_credentials_missing":
      return "This account has no Alpaca keys yet. Open it and add them."
    case "broker_auth_or_permissions_failed":
      return "Alpaca didn't accept these keys. Check that they are for a paper or live account as chosen."
    case "notification_webhook_invalid":
      return "That isn't a Discord webhook URL. Copy it again from the channel's settings."
    case "notification_webhook_unreachable":
      return "Discord didn't accept the webhook URL. It may have been deleted."
    case "notification_bot_identity_failed":
      return "Telegram didn't accept the bot token."
    case "notification_chat_access_failed":
      return "The bot can't reach that chat. Send the bot a message first, then try again."
    case "notification_credentials_missing":
    case "notification_identity_invalid":
    case "notification_auth_or_chat_access_failed":
      return "Couldn't reach the alert service. Check the token and the chat."
    case "removed_account_has_open_orders":
      return `${account} still has orders for ${stocks(check.symbols)} that CopyTrading placed. Let them fill or cancel them in Alpaca, or keep ${account} in the setup.`
    case "removed_account_needs_review":
      return `${account} still has a post being copied. Wait a moment, then check again, or keep ${account} in the setup.`
    case "removed_account_unreadable":
      return `CopyTrading couldn't read ${account}'s records to see what it still holds. Keep ${account} in the setup for now.`
    case "broker_keys_without_account":
      return `Alpaca keys were sent for ${account}, which isn't in the setup. Check the setup again.`
    case "routing_change_pending":
      return "Posts are still being read or sent. Wait a moment, then check again."
    case "pause_before_configuration_change":
      return "Pause copying before changing the setup."
    case ENGINE_UNAVAILABLE:
      return "CopyTrading couldn't run this check because its engine isn't answering. Wait for it to start, then try again."
    case "configuration_preflight_unavailable":
      return "Couldn't read CopyTrading's saved records to check the setup. Try again in a moment."
    default:
      return "Couldn't check this connection. Try again in a moment."
  }
}

/** What a check is about: "Discord", "Interpreter", "Alerts", an account by its name, or "Setup". */
export function checkTitle(check: CapabilityCheck): string {
  switch (check.name) {
    case "source":
      return "Discord"
    case "model":
      return "Interpreter"
    case "notification":
      return "Alerts"
    default:
      return check.subject ?? "Setup"
  }
}

/** What a passing check found, in words: never the engine's raw identity string. */
export function checkDetail(check: CapabilityCheck, modelName = ""): string | null {
  if (check.state === "failed") return connectionProblem(check, modelName)
  if (check.state !== "ready" || !check.identity) return null
  switch (check.name) {
    case "source":
      return "Signed in to Discord"
    case "model": {
      const [name, ...rest] = check.identity.split(":")
      const answered = rest.join(":")
      return answered ? `${isProvider(name!) ? PROVIDER_TITLES[name] : name} answered as ${answered}` : null
    }
    case "broker":
      return check.environment === "live" ? "Alpaca live account found" : "Alpaca paper account found"
    default:
      return null
  }
}
