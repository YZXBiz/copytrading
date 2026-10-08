import SwiftUI

/// An empty section as a small scene: one plain sentence, then the ground line drawn in with the
/// walker standing at its end.
struct InkEmptyState: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message)
                .font(DesignTokens.bodyText)
                .tracking(0.3)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            InkGround()
                .overlay(alignment: .bottomTrailing) {
                    InkWalker()
                        .padding(.trailing, 40)
                        .padding(.bottom, 3)
                }
        }
        .accessibilityElement(children: .combine)
    }
}
