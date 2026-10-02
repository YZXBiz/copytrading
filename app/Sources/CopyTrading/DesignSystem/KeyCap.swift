import SwiftUI

/// A key as it looks on the keyboard, for shortcut references: a small raised white cap.
struct KeyCap: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(DesignTokens.bodyEmphasis)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 24)
            .background(Palette.page, in: .rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
    }
}
