import SwiftUI

/// The numbers behind an account's result, each a small tinted chip with its label above its
/// value: "Your limit" "$201.00". One row when they fit, otherwise two columns.
struct ActivityFactChips: View {
    let facts: [ActivityCardOutcome.Fact]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in chip(fact) }
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(Array(stride(from: 0, to: facts.count, by: 2)), id: \.self) { start in
                    GridRow {
                        chip(facts[start]).frame(maxWidth: .infinity, alignment: .leading)
                        if start + 1 < facts.count {
                            chip(facts[start + 1]).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private func chip(_ fact: ActivityCardOutcome.Fact) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(fact.label)
                .font(DesignTokens.activityMeta)
                .foregroundStyle(Palette.secondaryInk)
            Text(fact.value)
                .font(DesignTokens.activityValue)
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.group, in: .rect(cornerRadius: DesignTokens.calloutCornerRadius))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}
