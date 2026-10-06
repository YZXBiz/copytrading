import DesktopCore
import Foundation

extension AgentProposal {
    /// What approving would do, in plain words.
    @MainActor
    var summary: String {
        switch subject {
        case .resumeAccount(let accountID):
            return L10n.string("Resume new entries in %@", accountID)
        case .setRecovery(let accountID, let preference):
            let title = RecoveryPreference(rawValue: preference)?.title ?? Humanize.code(preference)
            return L10n.string("In %@, after a restart: %@", accountID, title)
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
