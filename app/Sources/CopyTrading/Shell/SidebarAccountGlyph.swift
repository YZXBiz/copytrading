import DesktopCore
import SwiftUI

/// An account's small mark: blue for paper money, orange for real.
struct SidebarAccountGlyph: View {
    let environment: TradingEnvironment

    var body: some View {
        Image(systemName: "building.columns.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(environment == .live ? Color.orange : Palette.accent, in: .rect(cornerRadius: 5))
            .accessibilityHidden(true)
    }
}
