import DesktopCore
import SwiftUI

/// A guru's posts, newest first, under a heading for each day, rows split by hairlines.
struct GuruFeedList: View {
    let days: [GuruFeed.Day]
    let guruName: String
    @Binding var selection: SourceActivity.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("Posts"))
                    .font(DesignTokens.documentSubheading)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(L10n.string("Newest first"))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            }
            if days.isEmpty {
                Text(L10n.string("No posts from %@ yet. They show here as soon as CopyTrading reads one.", guruName))
                    .font(.body)
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.top, 16)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(days) { day in
                    GuruFeedDayLabel(start: day.start)
                        .padding(.top, 24)
                        .padding(.bottom, 4)
                    ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                        GuruFeedRow(
                            entry: entry, showsDivider: showsDivider(above: index, in: day), selection: $selection)
                    }
                }
            }
        }
    }

    /// Hairlines split rows, but never touch the highlighted one.
    private func showsDivider(above index: Int, in day: GuruFeed.Day) -> Bool {
        guard index > 0 else { return false }
        return selection != day.entries[index].id && selection != day.entries[index - 1].id
    }
}
