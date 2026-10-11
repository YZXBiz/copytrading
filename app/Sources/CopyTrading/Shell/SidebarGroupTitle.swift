import SwiftUI

/// The small capitals over a sidebar group: ACCOUNTS, PEOPLE.
struct SidebarGroupTitle: View {
    let title: String

    var body: some View {
        Text(L10n.string(title).uppercased())
            .font(DesignTokens.eyebrow)
            .tracking(DesignTokens.eyebrowTracking)
            .foregroundStyle(Palette.tertiaryInk)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}
