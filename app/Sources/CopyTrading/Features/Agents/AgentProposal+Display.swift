import DesktopCore
import Foundation

extension AgentProposal {
    /// What approving would do, in plain words.
    @MainActor
    var summary: String {
        switch subject {
        case .resumeAccount(let accountID):
            return L10n.string("Start copying into %@", accountID)
        case .setRecovery(let accountID, let preference):
            let title = RecoveryPreference(rawValue: preference)?.title ?? Humanize.code(preference)
            return L10n.string("In %@, after a restart: %@", accountID, title)
        case .startProcessing:
            return L10n.string("Start copying")
        case .applySetup:
            return L10n.string("Apply the setup, with live accounts")
        case .setAccountLimits(let accountID, let changes):
            let parts = changes.map { "\(Self.limitTitle($0.field)) \(Self.limitValue($0.field, $0.value))" }
            return L10n.string("In %@: %@", accountID, parts.joined(separator: ", "))
        case .manualOrder(let order):
            let orderType =
                order.limitPrice.map { L10n.string("limit %@", Humanize.usd($0)) }
                ?? L10n.string(Humanize.code(order.orderType).lowercased())
            return L10n.string(
                "%@ %@ %@, %@, in %@",
                L10n.string(Humanize.code(order.side)),
                String(describing: order.quantity),
                order.symbol,
                orderType,
                order.accountID
            )
        }
    }

    /// The approval sheet's title. A limits request lists each change in the sheet's rows, so its
    /// title only names the account; every other request reads as its summary.
    @MainActor
    var sheetTitle: String {
        if case .setAccountLimits(let accountID, _) = subject {
            return L10n.string("Change %@'s limits", accountID)
        }
        return summary
    }

    /// The account the request is about; nil when it starts copying the whole setup.
    var accountID: String? {
        switch subject {
        case .resumeAccount(let accountID), .setRecovery(let accountID, _), .setAccountLimits(let accountID, _):
            accountID
        case .manualOrder(let order):
            order.accountID
        case .startProcessing, .applySetup:
            nil
        }
    }

    /// The account sheet's own words for a setting, so a request reads like the page it changes.
    @MainActor
    static func limitTitle(_ field: String) -> String {
        let titles: [String: String] = [
            "max_order_usd": "Largest single buy",
            "max_symbol_usd": "Maximum per stock",
            "max_total_usd": "Maximum total exposure",
            "daily_loss_cap_usd": "Daily loss cap",
            "max_above_signal_pct": "Maximum above signal price (%)",
            "max_below_signal_pct": "Lowest sell price (% under the guru's)",
            "max_entries_per_day": "Entries per day",
            "max_signal_age_seconds": "Maximum signal age (seconds)",
            "order_timeout_seconds": "Order timeout (seconds)",
            "poll_seconds": "Check for posts every (seconds)",
            "extended_hours": "Trade in extended hours",
            "overnight": "Trade overnight",
            "copy_exits": "Copy exits",
            "approve_orders": "Ask me before sending orders",
        ]
        return L10n.string(titles[field] ?? Humanize.code(field))
    }

    @MainActor
    static func limitValue(_ field: String, _ value: String) -> String {
        switch value {
        case "true": return L10n.string("On")
        case "false": return L10n.string("Off")
        default:
            return ["max_order_usd", "max_symbol_usd", "max_total_usd", "daily_loss_cap_usd"].contains(field)
                ? Humanize.usd(value) : value
        }
    }

    /// Whether approving could spend real money; nil for requests that place no order.
    var environment: TradingEnvironment? {
        guard case .manualOrder(let order) = subject else { return nil }
        return order.environment
    }

    /// The program that asked, by name rather than path.
    @MainActor
    var requester: String {
        AgentCallerName.describe(requestedBy.path)
    }

    /// The sheet's heading: the in-app assistant names itself, any other program is "an agent".
    @MainActor
    var approvalHeading: String {
        AgentCallerName.isAssistant(requestedBy.path)
            ? L10n.string("The assistant is asking for approval") : L10n.string("An agent is asking for approval")
    }

    @MainActor
    var resultMessage: String {
        switch state {
        case .succeeded: L10n.string("Done: %@.", summary)
        case .failed: L10n.string("Could not complete: %@ (%@).", summary, L10n.string(Humanize.code(outcome?.code ?? "failed")))
        case .outcomeUnknown: L10n.string("Sent, but the result is not confirmed yet: %@. Check Accounts.", summary)
        case .expired: L10n.string("The request expired before approval.")
        case .pending, .running, .rejected, .discarded:
            L10n.string("%@: %@.", L10n.string(Humanize.code(state.rawValue)), summary)
        }
    }
}
