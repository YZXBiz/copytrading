import DesktopCore
import SwiftUI

/// A guru's posts as a two-column gallery, newest first across the top, each column taking the
/// next card while it is the shorter one, so the columns stay even. A narrow page shows one column.
struct GuruPostGallery: View {
    let entries: [GuruFeed.Entry]
    let guruName: String
    @Binding var selection: SourceActivity.ID?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                ForEach(Array(Self.columns(entries, count: 2).enumerated()), id: \.offset) { _, column in
                    stack(column)
                        .frame(minWidth: 300)
                }
            }
            stack(entries)
        }
    }

    private func stack(_ column: [GuruFeed.Entry]) -> some View {
        LazyVStack(spacing: 20) {
            ForEach(column) { entry in
                GuruPostCard(entry: entry, guruName: guruName, selection: $selection)
            }
        }
    }

    /// Deals entries into columns by a rough height: the quote's length and the account lines.
    static func columns(_ entries: [GuruFeed.Entry], count: Int) -> [[GuruFeed.Entry]] {
        var columns = Array(repeating: [GuruFeed.Entry](), count: count)
        var heights = Array(repeating: 0.0, count: count)
        for entry in entries {
            let target = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            columns[target].append(entry)
            let quoteLines = (Double(entry.item.readableText().count) / 26).rounded(.up)
            heights[target] += 150 + min(quoteLines, 6) * 32 + Double(max(entry.accounts.count, 1)) * 20
        }
        return columns
    }
}
