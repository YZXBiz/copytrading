import SwiftUI

/// One number in a guru's stats strip: the figure large in the display face, a small spaced label
/// in capitals under it.
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
            Text(item.label.uppercased())
                .font(DesignTokens.eyebrow)
                .tracking(DesignTokens.eyebrowTracking)
                .foregroundStyle(item.isCaution ? Palette.amber : Palette.tertiaryInk)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
