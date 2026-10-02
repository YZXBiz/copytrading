import SwiftUI

/// A compact round header control with a graphite symbol in a glass circle.
struct RoundGlassButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(Palette.ink)
                .frame(width: DesignTokens.headerControlSize, height: DesignTokens.headerControlSize)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(L10n.string(title))
        .accessibilityLabel(L10n.string(title))
    }
}
