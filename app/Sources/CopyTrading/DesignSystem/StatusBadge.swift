import SwiftUI

/// A status word after its tone's small symbol: no capsule, only the symbol carries the colour.
struct StatusBadge: View {
    let title: String
    let tone: StatusTone

    init(_ title: String, tone: StatusTone) {
        self.title = title
        self.tone = tone
    }

    var body: some View {
        Label {
            Text(L10n.string(title))
                .foregroundStyle(Palette.secondaryInk)
        } icon: {
            Image(systemName: tone.symbol)
                .foregroundStyle(tone.color)
        }
        .font(DesignTokens.caption)
        .imageScale(.small)
        .lineLimit(1)
        .fixedSize()
    }
}
