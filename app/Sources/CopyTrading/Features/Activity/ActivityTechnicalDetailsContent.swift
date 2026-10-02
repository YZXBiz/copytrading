import DesktopCore
import SwiftUI

/// What Technical details shows when opened: where the post stopped, who read it, and the Discord
/// IDs to look it up by, on one quiet grey surface.
struct ActivityTechnicalDetailsContent: View {
    let item: SourceActivity

    /// The model's raw note, only when the reading above did not already show it in full.
    private var parserNote: String? {
        guard let raw = item.parserReason?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return Reason.parserMessage(raw, needsReview: item.needsManualReview) == raw ? nil : raw
    }

    private var authorID: String? { item.authorID ?? item.sourceEvent.authorID }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ActivityPipelineTrack(item: item)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let interpretedBy = item.interpretedBy {
                    TechnicalFactRow(label: "Read by") { Text(interpretedBy) }
                }
                TechnicalFactRow(label: "Captured") { Text(Humanize.timestamp(item.capturedAt)) }
                if item.sourceRevision > 1 {
                    TechnicalFactRow(label: "Edits") {
                        Text(L10n.string("Edited %@ after posting", Humanize.count(item.sourceRevision - 1, "time")))
                    }
                }
                if item.profileRevision != nil {
                    TechnicalFactRow(label: "Guru version") {
                        Text(Humanize.revision(item.profileRevision))
                            .font(.system(.callout, design: .monospaced))
                    }
                }
                if let parserNote {
                    TechnicalFactRow(label: "Model's note") {
                        Text(parserNote)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("Discord IDs"))
                    .font(DesignTokens.caption.weight(.medium))
                    .foregroundStyle(Palette.secondaryInk)
                if let authorID {
                    CopyableIdentifierRow(label: "Author", value: authorID)
                }
                if let channelID = item.sourceEvent.channelID {
                    CopyableIdentifierRow(label: "Channel", value: channelID)
                }
                if let messageID = item.sourceEvent.messageID {
                    CopyableIdentifierRow(label: "Message", value: messageID)
                }
            }
            Label(L10n.string("Orders follow the reading above, not the raw text of the post."), systemImage: "info.circle")
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.group, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
        .padding(.top, 10)
    }
}
