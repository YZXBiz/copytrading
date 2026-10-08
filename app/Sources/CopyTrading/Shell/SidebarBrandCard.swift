import DesktopCore
import SwiftUI

/// The walker and the app's name at the top of the sidebar, like a studio's mark.
struct SidebarBrandCard: View {
    let model: AppModel

    @MainActor private var detail: String {
        guard let configuration = model.savedTradingConfiguration else { return L10n.string("Not set up yet") }
        let live = configuration.accounts.contains { $0.environment == .live }
        return L10n.string("%@ · %@", L10n.string(live ? "Live" : "Paper"), Humanize.count(configuration.accounts.count, "account"))
    }

    var body: some View {
        HStack(spacing: 10) {
            InkWalker()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.string("CopyTrading"))
                    .font(DisplayFont.font(size: 19, weight: .medium, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 19)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.string("CopyTrading, %@", detail))
    }
}
