import SwiftUI

/// A label and its value on one line, the label in a fixed column so values never wrap into a
/// narrow strip.
struct TechnicalFactRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(L10n.string(label))
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: 112, alignment: .leading)
            value
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
