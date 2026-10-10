import DesktopCore
import SwiftUI

/// The readable original post and separately captured source evidence.
struct ActivitySourceContentView: View {
    let item: SourceActivity
    /// The words the reader took each value from, marked where they appear (ADR-0007).
    var citedWords: [String] = []
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let said = item.readingText()
            if said.isEmpty {
                // An embed-only post has no body text, but its words follow right below; saying
                // nothing was captured above them would contradict what the reader can see.
                if item.readableSourceEmbeds.isEmpty {
                    Text(L10n.string("No message text was captured."))
                        .font(.body)
                        .foregroundStyle(Palette.secondaryInk)
                }
            } else {
                let attributed =
                    (try? AttributedString(
                        markdown: said,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                    )) ?? AttributedString(said)
                Text(quoted(marked(attributed)))
                    .font(DisplayFont.font(size: 24, relativeTo: .title2))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(L10n.string("Original post: %@", said))
            }

            ForEach(Array(item.readableSourceEmbeds.enumerated()), id: \.offset) { _, embed in
                ActivityCapturedEmbedView(embed: embed)
            }

            if !item.sourceEvent.attachments.isEmpty || item.sourceEvent.attachmentsOmitted > 0 {
                VStack(alignment: .leading, spacing: 9) {
                    ActivityLabel(text: L10n.string("Attachments"))
                    ForEach(Array(item.sourceEvent.attachments.enumerated()), id: \.offset) { _, attachment in
                        ActivityAttachmentEvidenceView(attachment: attachment)
                    }
                    if item.sourceEvent.attachmentsOmitted > 0 {
                        Text(L10n.string("%@ omitted", Humanize.count(item.sourceEvent.attachmentsOmitted, "attachment")))
                            .font(DesignTokens.caption)
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    /// The post between curly quotes, so it reads as the guru's line.
    private func quoted(_ text: AttributedString) -> AttributedString {
        AttributedString("\u{201C}") + text + AttributedString("\u{201D}")
    }

    /// The post with each cited word underlined in grey dots, quietly; words the post shows
    /// differently stay plain.
    private func marked(_ text: AttributedString) -> AttributedString {
        var text = text
        let plain = String(text.characters)
        for range in CitedWordMarks.ranges(of: citedWords, in: plain) {
            let start = text.characters.index(
                text.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: range.lowerBound))
            let end = text.characters.index(start, offsetBy: plain.distance(from: range.lowerBound, to: range.upperBound))
            text[start..<end].underlineStyle = Text.LineStyle(
                pattern: .dot, color: Palette.tertiaryInk.opacity(colorScheme == .dark ? 0.8 : 0.6))
        }
        return text
    }
}
