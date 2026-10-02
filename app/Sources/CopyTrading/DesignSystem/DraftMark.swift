import SwiftUI

/// A quiet note that something lives only in the setup so far: small grey words with a pencil.
struct DraftMark: View {
    var body: some View {
        Label(L10n.string("Not saved yet"), systemImage: "pencil")
            .font(DesignTokens.caption.weight(.medium))
            .foregroundStyle(Palette.tertiaryInk)
            .labelStyle(.titleAndIcon)
            .imageScale(.small)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Palette.page.opacity(0.7), in: .capsule)
    }
}
