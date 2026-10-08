import SwiftUI

/// A label and its value as one hairline row of a two-column table: the label in tracked capitals
/// in a fixed column, the value beside it, so every value starts at the same edge.
struct TechnicalFactRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ActivityLabel(text: L10n.string(label))
                    .frame(width: DesignTokens.factLabelWidth, alignment: .leading)
                value
                    .font(DesignTokens.activityBody)
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 9)
        }
        .accessibilityElement(children: .combine)
    }
}
