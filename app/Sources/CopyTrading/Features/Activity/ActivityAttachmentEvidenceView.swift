import DesktopCore
import SwiftUI

/// Compact file evidence captured with a source post.
struct ActivityAttachmentEvidenceView: View {
    let attachment: SourceAttachmentEvidence
    @Environment(\.sourcePictures) private var pictures

    var body: some View {
        if let image = pictures.image(for: attachment) {
            SourcePictureView(image: image)
        } else {
            named
        }
    }

    private var named: some View {
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
                // A picture inside an embed comes with no stated size, so only a known size shows.
                let size = attachment.byteSize ?? (attachment.declaredSize > 0 ? attachment.declaredSize : nil)
                let status = Humanize.code(attachment.status)
                Text(size.map { L10n.string("%@ · %@", Humanize.bytes(Int64($0)), status) } ?? status)
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
