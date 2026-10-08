import DesktopCore
import SwiftUI

/// An account's small mark, in quiet grey; a live account's mark is orange, since it trades real
/// money.
struct SidebarAccountGlyph: View {
    let environment: TradingEnvironment

    var body: some View {
        Image(systemName: "building.columns")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(environment == .live ? Color.orange : Palette.secondaryInk)
            .frame(width: 20, height: 20)
            .background(Palette.well, in: .rect(cornerRadius: 6))
            .accessibilityHidden(true)
    }
}
