import SwiftUI

/// A sheet's text-only action, such as Add Example or Remove: words in ink, no capsule. A
/// destructive one reads in red, the one colour that means "this takes something away".
struct SheetQuietButtonStyle: ButtonStyle {
    var isDestructive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.bodyEmphasis)
            .foregroundStyle(isDestructive ? StatusTone.critical.color : Palette.ink)
            .contentShape(.rect)
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.6 : 1)
    }
}
