import DesktopCore
import SwiftUI

/// A feed row's words: the guru's post in quotes, then how it was read in one line.
struct GuruFeedRowText: View {
    let entry: GuruFeed.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ActivitySourceText.formattedPreview(quoted))
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Text(entry.readAs)
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
        }
    }

    private var quoted: String {
        let text = entry.item.readableText()
        return text.isEmpty ? L10n.string("No message text") : "“\(text)”"
    }
}
