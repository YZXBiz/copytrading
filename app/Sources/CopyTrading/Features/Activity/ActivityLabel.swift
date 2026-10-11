import SwiftUI

/// A label in the page's tracked capitals, as the account page names Cash or Buying power:
/// "READ AS", "PRIMARY · PAPER", "TIMELINE". Labels only, never sentences.
struct ActivityLabel: View {
    /// Already localized; it is uppercased here.
    let text: String
    var color: Color = Palette.tertiaryInk

    var body: some View {
        Text(text.uppercased())
            .font(DesignTokens.eyebrow)
            .tracking(DesignTokens.eyebrowTracking)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}
