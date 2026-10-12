import SwiftUI

/// Why a call was not copied, stamped across its receipt in blush with an ink border.
struct RubberStamp: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .heavy))
            .tracking(1.2)
            .foregroundStyle(Palette.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Palette.blush.opacity(0.85))
            .overlay(Rectangle().strokeBorder(Palette.ink, lineWidth: 2))
            .rotationEffect(.degrees(-4))
            .padding(.horizontal, 8)
    }
}
