import SwiftUI

/// A small tinted capsule for a state: symbol plus word, never color alone.
struct Pill: View {
    let text: String
    let symbol: String
    var tint: Color

    var body: some View {
        Label(L10n.string(text), systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .imageScale(.small)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(0.13), in: .capsule)
            .fixedSize()
    }
}
