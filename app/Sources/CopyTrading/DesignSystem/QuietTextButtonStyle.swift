import SwiftUI

/// A secondary action as words alone, no pill or box: medium ink-grey text that the butter marker
/// sweeps under on hover. Beside it, at most one black capsule is the action a block asks for.
struct QuietTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietTextButtonLabel(configuration: configuration)
    }
}

/// The label the style draws, holding its own hover.
private struct QuietTextButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovers = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(DesignTokens.caption.weight(.semibold))
            .foregroundStyle(hovers && isEnabled ? Palette.ink : Palette.secondaryInk)
            .markerHighlight(hovers && isEnabled)
            .frame(minHeight: 28)
            .contentShape(.rect)
            .onHover { hovers = $0 }
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
