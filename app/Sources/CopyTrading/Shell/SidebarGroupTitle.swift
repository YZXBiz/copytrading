import SwiftUI

/// The small grey name over a sidebar group, in sentence case: Accounts, People.
struct SidebarGroupTitle: View {
    let title: String

    var body: some View {
        Text(L10n.string(title))
            .font(DesignTokens.label.weight(.semibold))
            .foregroundStyle(Palette.tertiaryInk)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}
