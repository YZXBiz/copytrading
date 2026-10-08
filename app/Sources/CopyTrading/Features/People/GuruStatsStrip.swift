import SwiftUI

/// Today's numbers for one guru in a hairline frame: posts, trades, calls waiting for the owner,
/// and how fast the reader reads them.
struct GuruStatsStrip: View {
    let stats: GuruStats

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(Palette.hairline)
                            .frame(width: 1)
                    }
                    GuruStatItem(item: item)
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 16) {
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
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius).stroke(Palette.hairline, lineWidth: 1))
    }

    private var items: [GuruStatItem.Item] {
        [
            .init(label: L10n.string("Posts today"), value: stats.postsToday.formatted()),
            .init(label: L10n.string("Traded"), value: stats.tradedToday.formatted()),
            .init(label: L10n.string("Waiting for you"), value: stats.waiting.formatted(), isCaution: stats.waiting > 0),
            .init(
                label: L10n.string("Read in"),
                value: stats.averageRead.map { L10n.string("%@ avg", PostTimeline.duration($0)) } ?? "—"),
        ]
    }
}
