import SwiftUI

/// Tint feedback without changing the size or weight of a native button's label.
struct FloatingControlButtonStyle: ButtonStyle {
    var isActive = false
    var minimumWidth: CGFloat = 0
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let isHighlighted = isEnabled && (isActive || isHovered || configuration.isPressed)
        configuration.label
            .padding(.horizontal, 8)
            .frame(minWidth: minimumWidth, minHeight: 32)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        configuration.isPressed && isEnabled
                            ? Palette.secondaryInk.opacity(0.16)
                            : Palette.sidebarSelection.opacity(isHighlighted ? 1 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(
                        Palette.secondaryInk.opacity(contrast == .increased && isHighlighted ? 1 : 0),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect(cornerRadius: 7))
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.45)
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHighlighted)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
