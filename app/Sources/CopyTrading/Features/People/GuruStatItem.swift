import SwiftUI

/// One number in a guru's stats strip: the figure large in the display face, a small grey label
/// under it.
struct GuruStatItem: View {
    struct Item {
        let label: String
        let value: String
        /// A quiet word after the figure, such as "avg".
        var suffix: String?
        var isCaution = false
    }

    let item: Item

    private static let figure = DisplayFont.font(size: 34, weight: .regular, relativeTo: .title)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.value)
                    .font(Self.figure)
                    .monospacedDigit()
                    .foregroundStyle(item.isCaution ? Palette.amber : Palette.ink)
                if let suffix = item.suffix {
                    Text(suffix)
                        .font(DesignTokens.lede)
                        .tracking(DesignTokens.ledeTracking)
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
            .lineLimit(1)
            Text(item.label)
                .font(DesignTokens.label)
                .foregroundStyle(item.isCaution ? Palette.amber : Palette.tertiaryInk)
                .lineLimit(1)
        }
        .fixedSize()
        // Named first, then the figure: "Posts today, 7", as a reading would be said.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
        .accessibilityValue(item.suffix.map { L10n.string("%@ %@", item.value, $0) } ?? item.value)
    }
}
