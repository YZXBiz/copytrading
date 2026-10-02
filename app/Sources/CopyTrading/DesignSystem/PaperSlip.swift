import SwiftUI

/// A small slip of paper for invitation drawings: a white card with a fine edge and a soft shadow,
/// tilted a little as if laid on the desk. Decorative.
struct PaperSlip<Content: View>: View {
    var tilt: Double = 0
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .padding(12)
            .background(colorScheme == .dark ? Color(white: 0.17) : .white, in: .rect(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.black.opacity(0.06)))
            .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
            .rotationEffect(.degrees(tilt))
            .accessibilityHidden(true)
    }
}
