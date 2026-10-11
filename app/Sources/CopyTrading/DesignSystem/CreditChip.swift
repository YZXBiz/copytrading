import SwiftUI

/// The white pill on a gallery tile's corner, the way a gallery credits its maker: who it was
/// (a guru, or the owner) in an ink ring, and when.
struct CreditChip: View {
    let name: String
    let time: String

    var body: some View {
        HStack(spacing: 8) {
            GuruMonogram(name: name, size: 22)
            Text(name)
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
