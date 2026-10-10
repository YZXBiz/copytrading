import SwiftUI

/// The page's own small buttons: a soft grey pill with no outline, or, for the one action a row
/// asks for, filled with ink. Colour on a page belongs to money, not to buttons.
struct PageButtonStyle: ButtonStyle {
    var isProminent = false
    /// Text buttons breathe; a lone symbol sits in a near-square.
    var horizontalPadding: CGFloat = 14
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.caption.weight(.medium))
            .foregroundStyle(isProminent ? Palette.page : Palette.ink)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: 28)
            .background(isProminent ? Palette.ink : Palette.well, in: .capsule)
            .overlay {
                if !isProminent, contrast == .increased {
                    Capsule().strokeBorder(Palette.secondaryInk)
                }
            }
            .contentShape(.capsule)
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
