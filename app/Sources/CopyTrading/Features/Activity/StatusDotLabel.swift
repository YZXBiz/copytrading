import SwiftUI

/// A quiet status: a small dot and the word, in the status's colour, where a pill would shout.
struct StatusDotLabel: View {
    let text: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone.color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(text)
                .font(DesignTokens.caption.weight(.medium))
                .foregroundStyle(tone.color)
                .lineLimit(1)
        }
        .fixedSize()
    }
}
