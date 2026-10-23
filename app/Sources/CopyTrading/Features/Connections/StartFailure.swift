import DesktopCore
import Foundation

/// Why copying didn't start, in a sentence or two for each thing that stopped it: which account
/// or service, what happened, and what to do. Accounts the engine couldn't open come first, each
/// by name; otherwise the engine's own reason names the service.
@MainActor
enum StartFailure {
    /// `modelService` names the interpreter, such as "DeepSeek".
    static func text(errorCode: String?, accounts: [TradingAccountStatus], modelService: String) -> String {
        let failed = accounts.filter { $0.state == "failed" }
        if !failed.isEmpty {
            // Accounts whose keys open one Alpaca account are said together, by name.
            let shared = failed.filter { $0.errorCode == sharedCode }.map(\.id)
            let rest = failed.filter { $0.errorCode != sharedCode }.map { account($0.id, $0.errorCode) }
            return ((shared.count > 1 ? [sharing(shared)] : shared.map { account($0, sharedCode) }) + rest)
                .joined(separator: " ")
        }
        return service(errorCode, modelService: modelService)
    }

    private static let sharedCode = "alpaca_account_shared"

    private static func sharing(_ names: [String]) -> String {
        let listed = L10n.string(
            "%@ and %@", names.dropLast().joined(separator: L10n.string(", ")), names[names.count - 1])
        return L10n.string(
            "%@ use keys for the same Alpaca account. Each account needs its own Alpaca account: remove one, or give it the keys of another.",
            listed)
    }

    private static let diagnostics = "If it happens again, Diagnostics at the bottom of the sidebar has the details."

    private static func account(_ name: String, _ code: String?) -> String {
        switch code {
        case "alpaca_account_shared":
            L10n.string(
                "%@ didn't open: another account in this setup uses keys for the same Alpaca account. Remove one of them, or give it the keys of another Alpaca account.",
                name)
        case "broker_keys_rejected":
            L10n.string("%@ didn't open: Alpaca didn't accept its API keys. Paste them again from your Alpaca dashboard.", name)
        case "broker_unreachable":
            L10n.string("%@ didn't open: Alpaca couldn't be reached. Check your internet connection, then start again.", name)
        case "account_in_use":
            L10n.string("%@ didn't open: another CopyTrading on this Mac is copying into it. Quit the other one, then start again.", name)
        case "outside_open_orders":
            L10n.string(
                "%@ didn't open: it has orders open at Alpaca that CopyTrading didn't place. Cancel them at Alpaca, then start again.", name
            )
        case "broker_account_inactive":
            L10n.string("%@ didn't open: Alpaca hasn't activated this account yet. Finish its setup at Alpaca, then start again.", name)
        default:
            L10n.string(
                "%@ didn't open, and CopyTrading couldn't tell why. Diagnostics at the bottom of the sidebar has the details.", name)
        }
    }

    private static func service(_ code: String?, modelService: String) -> String {
        switch code {
        case "source_unauthorized":
            L10n.string("Discord didn't accept your token. Copy a new one from Discord and paste it in Connections.")
        case "source_unavailable":
            L10n.string("Discord couldn't be reached. Check your internet connection, then start again.")
        case "provider_unavailable":
            L10n.string("%@ couldn't be reached. Check your internet connection and its API key, then start again.", modelService)
        case "routing_change_pending":
            L10n.string("Posts from your last setup were still being read or sent. Wait a minute, then start again.")
        case "account_ownership_pending":
            L10n.string("An account you removed still has an order or a copy under way. Wait for it to finish, then start again.")
        case "accounts_unavailable":
            L10n.string("More than one account didn't open. Accounts shows why for each one.")
        case "storage_unavailable", "routing_state_unavailable":
            L10n.string("%@. Quit and reopen CopyTrading.", Reason.text(code)) + " " + L10n.string(diagnostics)
        case nil, "processing_unavailable", "activation_journal_unavailable", "account_unavailable":
            L10n.string("CopyTrading stopped while starting. Start again.") + " " + L10n.string(diagnostics)
        default:
            L10n.string("%@. Start again.", Reason.text(code))
        }
    }
}
