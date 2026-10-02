import SwiftUI

/// A count over its label, as People's cards show a guru's calls, for the guide's picture of People.
struct GuideStat: View {
    let value: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value, format: .number)
                .font(DesignTokens.bodyEmphasis)
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
            Text(L10n.string(title))
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.secondaryInk)
        }
    }
}
