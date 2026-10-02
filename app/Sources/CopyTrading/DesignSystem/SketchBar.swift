import SwiftUI

/// A soft rounded bar standing in for text in an invitation drawing, so the drawing shows the
/// shape of what will appear without inventing numbers.
struct SketchBar: View {
    var width: CGFloat
    var height: CGFloat = 6
    var strength = 0.14

    var body: some View {
        Capsule()
            .fill(Palette.ink.opacity(strength))
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}
