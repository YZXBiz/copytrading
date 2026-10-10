import DesktopCore
import SwiftUI

/// "Paper" in a quiet outlined capsule; "Live" in orange, since it trades real money.
struct AccountModeBadge: View {
    let environment: TradingEnvironment

    private var isLive: Bool { environment == .live }

    var body: some View {
        Text(L10n.string(isLive ? "Live" : "Paper"))
            .font(DesignTokens.sidebarDetail.weight(.semibold))
            .foregroundStyle(isLive ? Color.orange : Palette.secondaryInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(isLive ? Color.orange.opacity(0.5) : Palette.hairline))
            .fixedSize()
    }
}
