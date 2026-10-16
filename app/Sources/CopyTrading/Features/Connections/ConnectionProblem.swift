import DesktopCore

/// What a failed connection check means, in one plain sentence that says what to do next.
enum ConnectionProblem {
    /// The app's own reason for a check the engine couldn't run.
    static let engineUnavailable = "check_engine_unavailable"

    /// - Parameter modelName: the model that was checked, for "has no model called …".
    @MainActor
    static func text(for check: TradingCapabilityCheck, modelName: String = "") -> String {
        let provider = TradingProviderName(rawValue: check.adapter)
        let service = provider?.shortTitle ?? check.adapter
        let account = check.subject ?? ""
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
        case "broker_keys_are_paper":
            return L10n.string("These are paper keys. Choose Paper, or enter this account's live keys.")
        case "broker_keys_are_live":
            return L10n.string("These are live keys, for real money. Choose Live, or enter paper keys.")
        case "broker_credentials_missing":
            return L10n.string("This account has no Alpaca keys yet. Open it and add them.")
        case "broker_auth_or_permissions_failed":
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
        case "removed_account_holds_shares":
            let one = check.symbols.count == 1
            return L10n.string(
                one
                    ? "%1$@ still holds %2$@ that CopyTrading bought. Sell it from %1$@'s page, or keep %1$@ in the setup."
                    : "%1$@ still holds %2$@ that CopyTrading bought. Sell them from %1$@'s page, or keep %1$@ in the setup.",
                account, stocks(check.symbols))
        case "removed_account_has_open_orders":
            return L10n.string(
                "%1$@ still has orders for %2$@ that CopyTrading placed. Let them fill or cancel them in Alpaca, or keep %1$@ in the setup.",
                account, stocks(check.symbols))
        case "removed_account_needs_review":
            return L10n.string(
                "%1$@ still has a post being copied or holdings to review. Open %1$@'s page to settle them, or keep %1$@ in the setup.",
                account)
        case "removed_account_unreadable":
            return L10n.string(
                "CopyTrading couldn't read %1$@'s records to see what it still holds. Keep %1$@ in the setup for now.", account)
        case "broker_keys_without_account":
            return L10n.string("Alpaca keys were sent for %@, which isn't in the setup. Check the setup again.", account)
        case "routing_change_pending":
            return L10n.string("Posts are still being read or sent. Wait a moment, then check again.")
        case "pause_before_configuration_change":
            return L10n.string("Pause copying before changing the setup.")
        case engineUnavailable:
            return L10n.string(
                "CopyTrading couldn't run this check because its engine isn't answering. Start it in Settings → Engine, then try again.")
        case "configuration_preflight_unavailable":
            return L10n.string("Couldn't read CopyTrading's saved records to check the setup. Try again in a moment.")
        default:
            return L10n.string("Couldn't check this connection. Try again in a moment.")
        }
    }

    /// "GFS, NVDA and WMT"; past four, the first three and how many more.
    @MainActor
    static func stocks(_ symbols: [String]) -> String {
        guard symbols.count > 4 else { return L10n.list(symbols) }
        return L10n.list(symbols.prefix(3) + [L10n.string("%lld more", symbols.count - 3)])
    }
}
