import SwiftUI

/// A label in small capitals spaced wide, like a studio site's navigation. Labels only, never
/// sentences.
struct Eyebrow: View {
    let text: String
    var color: Color = Palette.tertiaryInk

    init(_ text: String, color: Color = Palette.tertiaryInk) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(DesignTokens.eyebrow)
            .tracking(DesignTokens.eyebrowTracking)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}
