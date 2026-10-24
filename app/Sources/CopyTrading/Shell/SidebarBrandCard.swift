import SwiftUI

/// The app's name at the top of the sidebar as a wordmark, like a studio site's, and nothing under
/// it: the rows below already say which accounts there are and which are live.
struct SidebarBrandCard: View {
    var body: some View {
        Text(L10n.string("CopyTrading"))
            .font(DisplayFont.font(size: 21, weight: .medium, relativeTo: .headline))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 19)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .accessibilityAddTraits(.isHeader)
    }
}
