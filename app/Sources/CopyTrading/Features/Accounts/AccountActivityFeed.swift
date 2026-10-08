import DesktopCore
import SwiftUI

/// What happened in this account lately: each post that reached it and what came of it, newest
/// first. The full feed, with its filters and detail pane, builds on this.
struct AccountActivityFeed: View {
    let accountID: String
    let activity: [SourceActivity]
    let directory: GuruDirectory
    let selection: SourceActivity.ID?

    private static let shown = 12

    private var entries: [(post: SourceActivity, destination: DestinationActivity)] {
        activity.lazy
            .compactMap { post in post.destinations.first { $0.accountID == accountID }.map { (post, $0) } }
            .prefix(Self.shown)
            .map { $0 }
    }

    var body: some View {
        let entries = self.entries
        VStack(alignment: .leading, spacing: 8) {
            ListHeading("Activity")
            if entries.isEmpty {
                Text(L10n.string("Posts your gurus send to this account appear here, with what came of each."))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.post.id) { index, entry in
                        if index > 0 {
                            Hairline().padding(.leading, 48)
                        }
                        AccountActivityRow(
                            post: entry.post,
                            outcome: DestinationOutcome(entry.destination),
                            guruName: directory.name(for: entry.post.guruID),
                            isSelected: entry.post.id == selection
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.activity")
    }
}
