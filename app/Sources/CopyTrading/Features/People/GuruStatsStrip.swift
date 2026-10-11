import SwiftUI

/// Today's numbers for one guru, set in open space: posts, trades, calls waiting for the owner,
/// and how fast the reader reads them. Only a waiting call carries colour.
struct GuruStatsStrip: View {
    let stats: GuruStats

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 56) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    GuruStatItem(item: item)
                }
                Spacer(minLength: 0)
            }
            Grid(alignment: .leading, horizontalSpacing: 48, verticalSpacing: 24) {
                GridRow {
                    GuruStatItem(item: items[0])
                    GuruStatItem(item: items[1])
                }
                GridRow {
                    GuruStatItem(item: items[2])
                    GuruStatItem(item: items[3])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var items: [GuruStatItem.Item] {
        [
            .init(label: L10n.string("Posts today"), value: stats.postsToday.formatted()),
            .init(label: L10n.string("Traded"), value: stats.tradedToday.formatted()),
            .init(label: L10n.string("Waiting"), value: stats.waiting.formatted(), isCaution: stats.waiting > 0),
            .init(
                label: L10n.string("Read in"),
                value: stats.averageRead.map(PostTimeline.duration) ?? "—",
                suffix: stats.averageRead == nil ? nil : L10n.string("avg")),
        ]
    }
}
