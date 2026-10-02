import SwiftUI

/// A compact, tinted capsule that pairs a status word with its tone symbol.
struct StatusBadge: View {
    let title: String
    let tone: StatusTone

    init(_ title: String, tone: StatusTone) {
        self.title = title
        self.tone = tone
    }

    var body: some View {
        Label(L10n.string(title), systemImage: tone.symbol)
            .font(.callout)
            .imageScale(.small)
            .lineLimit(1)
            .foregroundStyle(tone.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tone.color.opacity(0.12), in: .capsule)
            .fixedSize()
    }
}
