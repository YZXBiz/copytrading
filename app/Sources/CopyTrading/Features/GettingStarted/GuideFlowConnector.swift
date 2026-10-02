import SwiftUI

/// The arrow between two stages of the opening figure; it brightens as the post passes through.
struct GuideFlowConnector: View {
    let isLit: Bool

    var body: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isLit ? Palette.accent : Palette.tertiaryInk)
            .frame(width: 18, height: 18)
            .padding(.top, 50)
            .symbolEffect(.bounce, value: isLit)
            .accessibilityHidden(true)
    }
}
