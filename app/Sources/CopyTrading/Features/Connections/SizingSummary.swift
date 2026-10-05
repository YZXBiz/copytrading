import DesktopCore
import Foundation

/// A few plain sentences for a guru's "Copies into" row: the guru's full position is the account's
/// maximum per stock, each call buys the guru's share of it, and the per-order limit only ever
/// trims a call, never sizes it. Amounts are what each call buys after that trim.
enum SizingSummary {
    @MainActor
    static func text(_ connection: TradingConnectionDraft, policy: TradingAccountPolicy?) -> String {
        let account = connection.accountID.trimmed.isEmpty ? L10n.string("this account") : connection.accountID.trimmed
        let full = policy?.maxSymbolUSD.trimmed ?? ""
        let terms = connection.terms(fullPositionUSD: full)
        guard let maximum = Decimal(string: full), maximum > 0,
            let sixth = terms.copiedBudgetUSD(sourceFraction: Decimal(1) / Decimal(6)),
            let half = terms.copiedBudgetUSD(sourceFraction: Decimal(1) / Decimal(2))
        else {
            return L10n.string("First set this account's max per stock. It's the guru's full position.")
        }
        // What each call buys once the per-order limit has trimmed it, as the engine does.
        let cap = policy.flatMap { Decimal(string: $0.maxOrderUSD.trimmed) }.flatMap { $0 > 0 ? $0 : nil }
        func bought(_ asked: Decimal) -> Decimal { cap.map { min(asked, $0) } ?? asked }
        let fallback = terms.copiedBudgetUSD(sourceFraction: nil)
        var sentences = [
            L10n.string("%@'s max per stock, **%@**, is this guru's full position.", account, dollars(maximum)),
            L10n.string("A 1/6 call buys **%@** and a 1/2 call **%@**.", dollars(bought(sixth)), dollars(bought(half))),
        ]
        if let cap, [sixth, half, fallback ?? 0].contains(where: { $0 > cap }) {
            sentences.append(
                L10n.string("Your max per order, **%@**, cuts bigger buys down. Activity shows when.", dollars(cap)))
        }
        if let fallback {
            sentences.append(L10n.string("A post with no size buys **%@**.", dollars(bought(fallback))))
        } else {
            sentences.append(L10n.string("A post with no size waits for you."))
        }
        return L10n.sentences(sentences)
    }

    /// Whole dollars without cents, as a person says an amount: "$40", "$41.66".
    private static func dollars(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }
}
