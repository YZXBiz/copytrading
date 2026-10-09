import SwiftUI

/// A sheet's one action, filled with ink and a size up from a page's small buttons; the quiet
/// variant is plain words beside it, such as Close, with no box.
struct InkActionButtonStyle: ButtonStyle {
    var isProminent = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.bodyEmphasis)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(isProminent ? Palette.page : Palette.secondaryInk)
            .padding(.horizontal, isProminent ? 22 : 6)
            .frame(minHeight: 38)
            .background(isProminent ? Palette.ink : .clear, in: .capsule)
            .contentShape(.capsule)
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
