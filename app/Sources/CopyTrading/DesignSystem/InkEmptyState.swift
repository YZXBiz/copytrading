import SwiftUI

/// An empty section as a small scene: one plain sentence, then the ground line drawn in.
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
        }
        .accessibilityElement(children: .combine)
    }
}
