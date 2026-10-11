import SwiftUI

/// A quiet secondary button: its title in secondary ink inside a hairline, no fill. Pressing dims it.
struct HairlineButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.caption.weight(.semibold))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hairline, lineWidth: 1))
            .contentShape(.rect(cornerRadius: 8))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
