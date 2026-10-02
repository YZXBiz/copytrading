import SwiftUI

/// What clicking a card lets you do next, drawn as a small accent capsule inside it. It is a
/// label, not a separate button: the whole card opens the editor.
struct InlineActionMark: View {
    let title: String

    var body: some View {
        Text(L10n.string(title))
            .font(DesignTokens.caption.weight(.semibold))
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Palette.accent.opacity(0.1), in: .capsule)
    }
}
