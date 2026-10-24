import SwiftUI

/// A small grey label in sentence case, as the account page names Cash or Buying power:
/// "Read as", "primary · Paper", "Timeline". Labels only, never sentences.
struct ActivityLabel: View {
    /// Already localized.
    let text: String
    var color: Color = Palette.tertiaryInk

    var body: some View {
        Text(text)
            .font(DesignTokens.label)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}
