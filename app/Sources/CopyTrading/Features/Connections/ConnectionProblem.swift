import DesktopCore

/// What a failed connection check means, in one plain sentence that says what to do next.
enum ConnectionProblem {
    /// - Parameter modelName: the model that was checked, for "has no model called …".
    @MainActor
    static func text(for check: TradingCapabilityCheck, modelName: String = "") -> String {
        let provider = TradingProviderName(rawValue: check.adapter)
        let service = provider?.shortTitle ?? check.adapter
        switch check.reasonCode {
        case "source_channel_access_denied", "source_history_permission_denied", "source_channel_not_readable":
            return L10n.string("Your Discord account can't read one of these channels. Check the channel IDs.")
        case "source_probe_timed_out", "source_history_probe_timed_out":
            return L10n.string("Discord didn't answer in time. Check your connection and try again.")
        case "source_identity_unavailable", "source_auth_or_channel_access", "source_history_read_failed":
            return L10n.string("Discord didn't accept the token, or can't find a channel. Check both.")
        case "model_key_rejected":
            return L10n.string("%@ didn't accept the API key.", service)
        case "model_not_found":
            return L10n.string("%@ has no model called “%@”.", service, modelName.trimmed)
        case "model_probe_rejected":
            return L10n.string("The model answered, but couldn't read a test post. Try another model.")
        case "model_unreachable" where provider == .ollama:
            return L10n.string("Nothing answered at that address. Check the Base URL and that %@ is running.", service)
        case "model_unreachable" where provider?.acceptsBaseURL == true:
            return L10n.string("Nothing answered at that address. Check the Base URL and that the server is running.")
        case "model_unreachable":
            return L10n.string("%@ didn't answer. Check your connection and try again.", service)
        case "model_auth_or_probe_failed":
            return L10n.string("Couldn't reach %@. Check the API key and your connection.", service)
        case "broker_account_not_tradeable":
            return L10n.string("Alpaca says this account can't trade yet. Check it on Alpaca's site.")
        case "broker_auth_or_permissions_failed", "broker_credentials_missing":
            return L10n.string("Alpaca didn't accept these keys. Check that they are for a paper or live account as chosen.")
        case "notification_webhook_invalid":
            return L10n.string("That isn't a Discord webhook URL. Copy it again from the channel's settings.")
        case "notification_webhook_unreachable":
            return L10n.string("Discord didn't accept the webhook URL. It may have been deleted.")
        case "notification_bot_identity_failed":
            return L10n.string("Telegram didn't accept the bot token.")
        case "notification_chat_access_failed":
            return L10n.string("The bot can't reach that chat. Send the bot a message first, then try again.")
        case "notification_credentials_missing", "notification_identity_invalid", "notification_auth_or_chat_access_failed":
            return L10n.string("Couldn't reach the alert service. Check the token and the chat.")
        default:
            return L10n.string("Couldn't check this connection. Try again in a moment.")
        }
    }
}
