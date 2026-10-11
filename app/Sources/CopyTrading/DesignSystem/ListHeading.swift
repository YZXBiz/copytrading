import SwiftUI

/// A page section's title in plain regular type, an optional count beside it in grey, and quiet words or controls at
/// the trailing edge.
struct ListHeading<Trailing: View>: View {
    let title: String
    var count = 0
    @ViewBuilder let trailing: Trailing

    init(_ title: String, count: Int = 0, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.count = count
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L10n.string(title))
                .font(DesignTokens.listHeading)
                .tracking(DesignTokens.listHeadingTracking)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if count > 0 {
                Text(count.formatted())
                    .font(DesignTokens.listHeading)
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiaryInk)
            }
            Spacer(minLength: 12)
            trailing
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
        }
    }
}
