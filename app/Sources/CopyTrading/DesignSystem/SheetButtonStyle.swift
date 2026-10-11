import SwiftUI

/// The buttons in a sheet's bottom bar: the one answer, a capsule filled with ink, and beside it
/// the way out as plain words.
struct SheetButtonStyle: ButtonStyle {
    var isPrimary = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.bodyEmphasis)
            .foregroundStyle(isPrimary ? Palette.page : Palette.ink)
            .padding(.horizontal, isPrimary ? 20 : 6)
            .frame(minHeight: 34)
            .background {
                if isPrimary { Capsule().fill(Palette.ink) }
            }
            .underline(!isPrimary && contrast == .increased)
            .contentShape(.rect)
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
