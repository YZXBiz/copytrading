import DesktopCore
import SwiftUI

/// One thing that happened in the account, on its timeline: the time and who did it in the gutter,
/// what happened in a sentence, and the dollars that moved in the column on the right. The dot is
/// butter for a trade. A row that came from a guru's post is marked in butter under the pointer,
/// shows its ↗, and opens the post.
struct AccountFeedRow: View {
    let item: AccountFeedItem
    let directory: GuruDirectory
    let place: TimelinePlace
    let isSelected: Bool
    /// Opens the post the row came from; nil when the owner did it or the post is gone.
    let open: (() -> Void)?
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let figure = DisplayFont.font(size: 26, weight: .regular, relativeTo: .title2)

    var body: some View {
        if let open {
            Button(action: open) { row }
                .buttonStyle(QuietPressButtonStyle())
                .onHover { isHovered = $0 }
                .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isHovered)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(L10n.string("Open the original post, interpretation, and account results."))
        } else {
            row
        }
    }

    private var isMarked: Bool { open != nil && (isHovered || isSelected) }

    private var row: some View {
        TimelineRow(
            mark: item.isTrade ? .traded : .quiet, runsAbove: true, runsBelow: place.runsBelow, isWide: place.isWide,
            trailingWidth: 180
        ) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(item.time)
                    .font(DesignTokens.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiaryInk)
                Text(item.credit(directory))
                    .font(DesignTokens.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .lineLimit(1)
        } content: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.sentence)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .markerHighlight(isMarked)
                if open != nil {
                    OpenArrow(isShown: isMarked)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                }
            }
        } trailing: {
            if item.isTrade, let amount = Decimal(engine: item.amount) {
                Text(amount, format: .currency(code: "USD"))
                    .font(Self.figure)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
