import DesktopCore
import SwiftUI

/// A feed row's words: the guru's post in quotes, set large like a title in a list of works, then
/// how it was read in one quiet line.
struct GuruFeedRowText: View {
    let entry: GuruFeed.Entry

    private static let quote = Font.system(.body).scaled(by: 17.0 / 13)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ActivitySourceText.formattedPreview(quoted))
                .font(Self.quote)
                .foregroundStyle(Palette.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Text(entry.readAs)
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .lineLimit(1)
        }
    }

    private var quoted: String {
        let text = entry.item.readableText()
        return text.isEmpty ? L10n.string("No message text") : "“\(text)”"
    }
}
