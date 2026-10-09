import SwiftUI

/// The white pill on a post card's corner, the way a gallery credits its maker: the guru's ring
/// and name, and when they posted.
struct GuruPostChip: View {
    let guruName: String
    let time: String

    var body: some View {
        HStack(spacing: 8) {
            GuruMonogram(name: guruName, size: 22)
            Text(guruName)
                .font(DesignTokens.bodyEmphasis)
                .foregroundStyle(Palette.ink)
            Text(time)
                .font(DesignTokens.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.tertiaryInk)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Palette.page, in: .capsule)
        .overlay(Capsule().strokeBorder(Palette.hairline))
        .accessibilityElement(children: .combine)
    }
}
