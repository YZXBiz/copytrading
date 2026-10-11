import DesktopCore
import Foundation

/// What a guru's calls come to in the account they copy into, as figures: the guru's full position
/// (the account's maximum per stock), then what a 1/6 call, a 1/2 call, and a call with no size
/// each buy once the per-order limit has trimmed them, as the engine trims them.
struct SizingSummary: Equatable {
    struct Figure: Equatable, Identifiable {
        let label: String
        let amount: String
        /// The per-order limit cut this one down.
        let isTrimmed: Bool
        var id: String { label }
    }

    let figures: [Figure]
    /// One quiet line: what the per-order limit does, when it trims anything.
    let note: String?

    /// Nil until the account has a maximum per stock, which is the guru's full position.
    @MainActor
    static func of(_ connection: TradingConnectionDraft, policy: TradingAccountPolicy?) -> Self? {
        let full = policy?.maxSymbolUSD.trimmed ?? ""
        let terms = connection.terms(fullPositionUSD: full)
        guard let maximum = Decimal(string: full), maximum > 0,
            let sixth = terms.copiedBudgetUSD(sourceFraction: Decimal(1) / Decimal(6)),
            let half = terms.copiedBudgetUSD(sourceFraction: Decimal(1) / Decimal(2)),
            // A post with no size asks for the full position (ADR-0010).
            let whole = terms.copiedBudgetUSD(sourceFraction: nil)
        else { return nil }
        let cap = policy.flatMap { Decimal(string: $0.maxOrderUSD.trimmed) }.flatMap { $0 > 0 ? $0 : nil }
        func figure(_ label: String, _ asked: Decimal) -> Figure {
            let trimmed = cap.map { asked > $0 } ?? false
            return Figure(label: L10n.string(label), amount: dollars(trimmed ? cap ?? asked : asked), isTrimmed: trimmed)
        }
        let figures = [
            Figure(label: L10n.string("Full position"), amount: dollars(maximum), isTrimmed: false),
            figure("A 1/6 call", sixth),
            figure("A 1/2 call", half),
            figure("No size given", whole),
        ]
        let note =
            figures.contains(where: \.isTrimmed)
            ? cap.map { L10n.string("Your max per order, %@, caps any one buy.", dollars($0)) } : nil
        return Self(figures: figures, note: note)
    }

    /// Whole dollars without cents, as a person says an amount: "$40", "$41.66".
    private static func dollars(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }
}
