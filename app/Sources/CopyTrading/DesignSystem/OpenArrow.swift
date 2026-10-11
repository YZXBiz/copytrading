import SwiftUI

/// The thin ↗ a studio site sets beside a work's title: it fades in and nudges toward the corner
/// under the pointer, saying the tile opens.
struct OpenArrow: View {
    let isShown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "arrow.up.right")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(Palette.ink)
            .opacity(isShown ? 1 : 0)
            .offset(x: isShown ? 0 : -6, y: isShown ? 0 : 6)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: isShown)
            .accessibilityHidden(true)
    }
}
