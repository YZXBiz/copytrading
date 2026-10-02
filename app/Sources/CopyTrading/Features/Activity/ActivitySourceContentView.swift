import DesktopCore
import SwiftUI

/// The readable original post and separately captured source evidence.
struct ActivitySourceContentView: View {
    let item: SourceActivity
    @ScaledMetric(relativeTo: .body) private var readingBodySize = 17

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
                Text(attributed)
                    .font(.system(size: readingBodySize))
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
                    Text(L10n.string("Attachments"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.secondaryInk)
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

}
