import SwiftUI

/// A small symbol on a soft disc of its own colour: the mark at the start of a feed row.
struct ToneGlyph: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.13), in: .circle)
            .accessibilityHidden(true)
    }
}
