import DesktopCore
import SwiftUI

/// Compact file evidence captured with a source post.
struct ActivityAttachmentEvidenceView: View {
    let attachment: SourceAttachmentEvidence

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "paperclip")
                .foregroundStyle(Palette.tertiaryInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if !attachment.filename.isEmpty {
                    Text(attachment.filename)
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let size = Humanize.bytes(Int64(attachment.byteSize ?? attachment.declaredSize))
                let status = Humanize.code(attachment.status)
                Text(L10n.string("%@ · %@", size, status))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
