import SwiftUI

/// The page's own small buttons: a hairline outline in secondary ink, or, for the one action a
/// row asks for, filled with the accent.
struct PageButtonStyle: ButtonStyle {
    var isProminent = false
    /// Text buttons breathe; a lone symbol sits in a near-square.
    var horizontalPadding: CGFloat = 12
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.caption.weight(.semibold))
            .foregroundStyle(isProminent ? Color.white : Palette.secondaryInk)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: 26)
            .background(isProminent ? Palette.accent : .clear, in: .rect(cornerRadius: 7))
            .overlay {
                if !isProminent {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(contrast == .increased ? Palette.secondaryInk : Palette.hairline)
                }
            }
            .contentShape(.rect(cornerRadius: 7))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
