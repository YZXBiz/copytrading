import DesktopCore
import Foundation

/// What a guru's calls come to in the account they copy into, as figures: what a 1/6 call, a 1/2
/// call, and a call with no size each buy from the guru's full position once the account's largest
/// single buy has cut them, as the engine cuts them (ADR-0010).
struct SizingSummary: Equatable {
    struct Figure: Equatable, Identifiable {
        let label: String
        let amount: String
        /// What the call asked for, when the largest single buy cut it down to `amount`.
        let cutFrom: String?
        var isTrimmed: Bool { cutFrom != nil }
        var id: String { label }
    }

    let figures: [Figure]
    /// One quiet line: what the largest single buy does, when it cuts anything.
    let note: String?
    /// The full position is above the account's maximum per stock, so a buy stops at that limit.
    let warning: String?

    /// Nil until the guru has a full position: its own, or the account's maximum per stock.
    @MainActor
    static func of(_ connection: TradingConnectionDraft, policy: TradingAccountPolicy?) -> Self? {
        let maximum = policy?.maxSymbolUSD.trimmed ?? ""
        let fullText = connection.fullPositionUSD.trimmed.nilIfEmpty ?? maximum
        let terms = connection.terms(fullPositionUSD: fullText)
        let cap = policy.flatMap { Decimal(string: $0.maxOrderUSD.trimmed) }.flatMap { $0 > 0 ? $0 : nil }
        guard let full = Decimal(string: fullText), full > 0,
            let sixth = terms.copiedBudgetUSD(sourceFraction: Decimal(1) / Decimal(6), unsizedUSD: cap),
            let half = terms.copiedBudgetUSD(sourceFraction: Decimal(1) / Decimal(2), unsizedUSD: cap),
            // A post with no size buys the largest single buy (ADR-0010); without one, the full position.
            let unsized = terms.copiedBudgetUSD(sourceFraction: nil, unsizedUSD: cap ?? full)
        else { return nil }
        func figure(_ label: String, _ asked: Decimal) -> Figure {
            let trimmed = cap.map { asked > $0 } ?? false
            return Figure(
                label: L10n.string(label), amount: dollars(trimmed ? cap ?? asked : asked),
                cutFrom: trimmed ? dollars(asked) : nil)
        }
        let figures = [figure("A 1/6 call", sixth), figure("A 1/2 call", half), figure("No size given", unsized)]
        let note =
            figures.contains(where: \.isTrimmed)
            ? cap.map { L10n.string("Your largest single buy, %@, caps any one buy.", dollars($0)) } : nil
        let warning = Decimal(string: maximum).flatMap { limit in
            full > limit ? L10n.string("Above this account's %@ limit for one stock: buys stop there.", dollars(limit)) : nil
        }
        return Self(figures: figures, note: note, warning: warning)
    }

    /// Whole dollars without cents, as a person says an amount: "$40", "$41.66".
    private static func dollars(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }
}
