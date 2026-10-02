import SwiftUI

/// A rounded tag: neutral grey for facts, tinted when it carries a state.
struct Chip: View {
    let text: String
    var symbol: String?
    var tint: Color?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.callout)
        .lineLimit(1)
        .foregroundStyle(tint ?? Palette.ink.opacity(0.8))
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background((tint ?? Color.secondary).opacity(tint == nil ? 0.1 : 0.12), in: .rect(cornerRadius: 6))
        .fixedSize()
    }
}
