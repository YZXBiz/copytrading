import SwiftUI

/// A framed card: a softly tinted inside within a white frame, continuous
/// corners, and a shadow that lifts a little on hover.
struct FramedCard<Content: View>: View {
    var tint: Color
    var isHovered = false
    @ViewBuilder let content: Content
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint, in: .rect(cornerRadius: 15, style: .continuous))
            .padding(6)
            .background(Palette.page, in: .rect(cornerRadius: 21, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .strokeBorder(contrast == .increased ? Palette.secondaryInk : .black.opacity(0.05), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(isHovered ? 0.1 : 0.05), radius: isHovered ? 14 : 9, y: isHovered ? 5 : 3)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isHovered)
            .contentShape(.rect(cornerRadius: 21, style: .continuous))
    }
}
