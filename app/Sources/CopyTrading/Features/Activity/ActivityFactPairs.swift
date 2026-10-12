import SwiftUI

/// The numbers behind an account's result as plain pairs, a tracked-capital label over its value:
/// "YOUR LIMIT" "$201.00". One row when they fit, otherwise two columns. No chips, no fill.
struct ActivityFactPairs: View {
    let facts: [ActivityCardOutcome.Fact]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in pair(fact) }
            }
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
                ForEach(Array(stride(from: 0, to: facts.count, by: 2)), id: \.self) { start in
                    GridRow {
                        pair(facts[start])
                        if start + 1 < facts.count {
                            pair(facts[start + 1])
                        }
                    }
                }
            }
        }
    }

    private func pair(_ fact: ActivityCardOutcome.Fact) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ActivityLabel(text: fact.label)
            Text(fact.value)
                .font(DesignTokens.statValue)
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
