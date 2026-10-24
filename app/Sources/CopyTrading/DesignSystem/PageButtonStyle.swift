import SwiftUI

/// The page's own small buttons: a soft grey pill with no outline; an outlined pill for an answer
/// that repeats down a list, such as each lot's Sell; or, for the one action a screen asks for,
/// filled with ink. A screen has at most one ink capsule. Colour on a page belongs to money, not
/// to buttons.
struct PageButtonStyle: ButtonStyle {
    enum Emphasis {
        /// A soft grey pill.
        case standard
        /// A hairline outline on nothing, quieter than the grey pill where many sit in a column.
        case outlined
        /// Filled with ink: the screen's one primary action.
        case prominent
    }

    var emphasis = Emphasis.standard
    /// Text buttons breathe; a lone symbol sits in a near-square.
    var horizontalPadding: CGFloat = 14
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.caption.weight(.medium))
            .foregroundStyle(emphasis == .prominent ? Palette.page : Palette.ink)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: 28)
            .background(background, in: .capsule)
            .overlay {
                if emphasis == .outlined {
                    Capsule().strokeBorder(contrast == .increased ? Palette.secondaryInk : Palette.ink.opacity(0.18))
                } else if emphasis == .standard, contrast == .increased {
                    Capsule().strokeBorder(Palette.secondaryInk)
                }
            }
            .contentShape(.capsule)
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var background: Color {
        switch emphasis {
        case .standard: Palette.well
        case .outlined: .clear
        case .prominent: Palette.ink
        }
    }
}
