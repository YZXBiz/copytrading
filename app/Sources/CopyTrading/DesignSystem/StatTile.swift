import SwiftUI

/// One figure under a headline number: a quiet caption above the value, no box and no icon.
struct StatTile<Value: View>: View {
    let title: String
    @ViewBuilder let value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.string(title))
                .font(.system(size: 12))
                .foregroundStyle(Palette.tertiaryInk)
            value
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
