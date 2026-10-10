import DesktopCore
import SwiftUI

struct ExampleComparisonRow: View {
    let example: ProfileExampleComparison

    @MainActor private var actualText: String {
        if let instruction = example.actual.instructions.first {
            return L10n.string(
                "%@ %@ · fraction %@",
                L10n.string(Humanize.code(instruction.action.rawValue)),
                instruction.symbol,
                instruction.fraction.map(Humanize.fraction) ?? L10n.string("none")
            )
        }
        return L10n.string(
            "%@ · %@", L10n.string(Humanize.code(example.actual.decision)),
            L10n.string(Humanize.code(example.actual.reason))
        )
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
                    Text(
                        L10n.string(
                            "%@ %@ · fraction %@",
                            L10n.string(Humanize.code(example.expectedAction.rawValue)), example.expectedSymbol,
                            example.expectedFraction.map(Humanize.fraction) ?? L10n.string("none")
                        )
                    )
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
            ForEach(example.reviewReasons, id: \.self) { reason in
                Text(Reason.text(reason))
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 10)
    }
}
