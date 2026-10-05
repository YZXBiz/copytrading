import DesktopCore
import Foundation

/// One plain sentence for a guru's "Copies into" row: the guru's full position is the account's
/// maximum per stock, each call buys the guru's share of it, and the per-order limit only ever
/// trims a call, never sizes it.
enum SizingSummary {
    @MainActor
    static func text(_ connection: TradingConnectionDraft, policy: TradingAccountPolicy?) -> String {
        let account = connection.accountID.trimmed.isEmpty ? L10n.string("this account") : connection.accountID.trimmed
        let full = policy?.maxSymbolUSD.trimmed ?? ""
        let terms = TradingRouteConnection(
            accountID: connection.accountID,
            mode: .proportional,
            amountUSD: full,
            defaultFraction: connection.useDefaultFraction ? connection.defaultFraction.trimmed : nil
        )
        guard let maximum = Decimal(string: full), maximum > 0,
            let sixth = terms.copiedBudgetUSD(sourceFraction: Decimal(1) / Decimal(6)),
            let half = terms.copiedBudgetUSD(sourceFraction: Decimal(1) / Decimal(2))
        else {
            return L10n.string("Set this account's maximum per stock first: it is the guru's full position.")
        }
        var sentences = [
            L10n.string(
                "The guru's full position is %@'s maximum per stock, **%@**. A 1/6 call buys **%@**, a 1/2 call **%@**.",
                account, dollars(maximum), dollars(sixth), dollars(half))
        ]
        if let cap = policy.flatMap({ Decimal(string: $0.maxOrderUSD.trimmed) }), cap > 0, half > cap {
            sentences.append(
                L10n.string(
                    "Its per-order limit, **%@**, cuts any call bigger than that, and Activity says when it does.",
                    dollars(cap)))
        }
        if let fallback = terms.copiedBudgetUSD(sourceFraction: nil) {
            sentences.append(L10n.string("A call that names no size buys **%@**.", dollars(fallback)))
        } else {
            sentences.append(L10n.string("A call that names no size waits for you to review it."))
        }
        return sentences.joined(separator: " ")
    }

    /// Whole dollars without cents, as a person says an amount: "$40", "$41.66".
    private static func dollars(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }
}
