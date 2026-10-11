import SwiftUI

/// A status as a drawn dot: the tone's riso fill inside an ink outline, or a hollow ring while it
/// waits. The word beside it says the state, so the dot never carries meaning alone.
struct ToneDot: View {
    let tone: StatusTone
    var size: CGFloat = 11

    var body: some View {
        Circle()
            .fill(tone.fill ?? Palette.page)
            .overlay(
                Circle().strokeBorder(
                    tone.fill == nil ? Palette.tertiaryInk.opacity(0.6) : Palette.ink, lineWidth: 1.2)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
