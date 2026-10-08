import SwiftUI

/// One number in a guru's stats strip, its label above it.
struct GuruStatItem: View {
    struct Item {
        let label: String
        let value: String
        var isCaution = false
    }

    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.label)
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
            Text(item.value)
                .font(DesignTokens.activityHeadline)
                .monospacedDigit()
                .foregroundStyle(item.isCaution ? Palette.amber : Palette.ink)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
