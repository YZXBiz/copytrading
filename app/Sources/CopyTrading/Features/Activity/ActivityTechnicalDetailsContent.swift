import DesktopCore
import SwiftUI

/// What Technical details shows when opened: the post's timed trip from Discord to the broker,
/// each order's facts, who read it, and the Discord IDs to look it up by, as hairline rows on the
/// page with no frame.
struct ActivityTechnicalDetailsContent: View {
    let item: SourceActivity
    @Environment(\.postProgressContext) private var progressContext

    /// The model's raw note, only when the reading above did not already show it in full.
    private var parserNote: String? {
        guard let raw = item.parserReason?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return Reason.parserMessage(raw, needsReview: item.needsManualReview) == raw ? nil : raw
    }

    private var authorID: String? { item.authorID ?? item.sourceEvent.authorID }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 0) {
                TechnicalSectionTitle(text: L10n.string("Timeline"))
                ActivityTimelineView(timeline: PostTimeline(item), progress: PostProgress(item, context: progressContext))
            }
            ForEach(item.destinations) { destination in
                ForEach(destination.orders) { order in
                    OrderFactsView(order: order, account: destination.accountID)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                TechnicalSectionTitle(text: L10n.string("Reading"))
                if let interpretedBy = item.interpretedBy {
                    TechnicalFactRow(label: "Read by") { Text(interpretedBy) }
                }
                if item.sourceRevision > 1 {
                    TechnicalFactRow(label: "Edits") {
                        Text(L10n.string("Edited %@ after posting", Humanize.count(item.sourceRevision - 1, "time")))
                    }
                }
                if item.profileRevision != nil {
                    TechnicalFactRow(label: "Guru version") {
                        Text(Humanize.revision(item.profileRevision))
                            .font(DesignTokens.activityIdentifier)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                if let parserNote {
                    TechnicalFactRow(label: "Model's note") {
                        Text(parserNote)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                TechnicalSectionTitle(text: L10n.string("Discord IDs"))
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
            Text(L10n.string("Orders follow the reading above, not the raw text of the post."))
                .font(DesignTokens.activityMeta)
                .foregroundStyle(Palette.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
