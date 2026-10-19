import DesktopCore
import SwiftUI

struct ExampleComparisonRow: View {
    let example: ProfileExampleComparison

    @MainActor private var actualText: String {
        if let instruction = example.actual.instructions.first {
            return Self.call(
                L10n.string(Humanize.code(instruction.action.rawValue)), instruction.symbol, instruction.fraction)
        }
        return L10n.string(
            "%@ · %@", L10n.string(Humanize.code(example.actual.decision)), Reason.text(example.actual.reason)
        )
    }

    /// "Sell all NFXL · fraction 1"; a buy that names no fraction is just "Buy NBIS".
    @MainActor private static func call(_ action: String, _ symbol: String, _ fraction: String?) -> String {
        guard let fraction else { return L10n.string("%@ %@", action, symbol) }
        return L10n.string("%@ %@ · fraction %@", action, symbol, Humanize.fraction(fraction))
    }

    /// The reasons beyond what the rows already say: "Mismatch" covers a reading that is not one
    /// trade, and the model row names why it was not.
    private var extraReasons: [String] {
        let shown: Set<String> = [
            "example_did_not_produce_trade", "example_requires_exactly_one_instruction", example.actual.reason,
        ]
        return example.reviewReasons.filter { !shown.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("Example %lld", Int64(example.exampleIndex + 1)))
                    .font(DesignTokens.bodyEmphasis)
                Spacer()
                StatusBadge(example.matches ? "Matches" : "Mismatch", tone: example.matches ? .positive : .caution)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                GridRow {
                    Text(L10n.string("Expected")).foregroundStyle(Palette.tertiaryInk)
                    Text(Self.call(example.expectedAction.title, example.expectedSymbol, example.expectedFraction))
                }
                GridRow {
                    Text(L10n.string("Model")).foregroundStyle(Palette.tertiaryInk)
                    Text(actualText)
                }
                ForEach(example.actual.destinations, id: \.accountID) { destination in
                    GridRow {
                        Text(destination.accountID).foregroundStyle(Palette.tertiaryInk)
                        Text(destination.budgetUSD.map(Humanize.usd) ?? Reason.text(destination.reason))
                    }
                }
            }
            .font(DesignTokens.caption)
            ForEach(extraReasons, id: \.self) { reason in
                Text(Reason.text(reason))
                    .font(.callout)
                    .foregroundStyle(Palette.live)
            }
        }
        .padding(.vertical, 10)
    }
}
