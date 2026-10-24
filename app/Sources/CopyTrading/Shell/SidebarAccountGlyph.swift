import DesktopCore
import SwiftUI

/// An account's small mark, a bare line glyph in quiet grey with no tile behind it; a live
/// account's mark is orange, since it trades real money.
struct SidebarAccountGlyph: View {
    let environment: TradingEnvironment

    var body: some View {
        Image(systemName: "building.columns")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(environment == .live ? Palette.live : Palette.tertiaryInk)
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}
