import SwiftUI

/// The look of the page-header controls: a graphite symbol on a small white rounded square.
/// `SquareHeaderButton` and header menus draw with it.
struct SquareControlLabel: View {
    let symbol: String
    var isHovered = false
    /// White on a backdrop such as Connections' chart paper; a soft grey on a plain panel.
    var fill = Palette.page
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Palette.ink)
            .frame(width: DesignTokens.squareControlSize, height: DesignTokens.squareControlSize)
            .background(fill.opacity(isHovered ? 1 : 0.92), in: .rect(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(contrast == .increased ? Palette.secondaryInk : .black.opacity(0.04), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isHovered ? 0.1 : 0.05), radius: isHovered ? 6 : 3, y: 1)
            .contentShape(.rect(cornerRadius: 11))
    }
}
