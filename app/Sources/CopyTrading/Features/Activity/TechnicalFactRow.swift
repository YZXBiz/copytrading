import SwiftUI

/// A label and its value as one row of a two-column table: the label in a fixed column, the value
/// beside it, so every value starts at the same edge.
struct TechnicalFactRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(L10n.string(label))
                .font(DesignTokens.activityMeta)
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: DesignTokens.factLabelWidth, alignment: .leading)
            value
                .font(DesignTokens.activityBody)
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
