import SwiftUI

/// A row in the menu bar panel that behaves like a native menu item: a symbol, a title, an
/// optional shortcut hint, and a soft highlight under the pointer.
struct MenuRow: View {
    let title: String
    let symbol: String
    var shortcut: String?
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(L10n.string(title))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(hovering && isEnabled ? Palette.sidebarSelection : .clear, in: .rect(cornerRadius: 6))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
            .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { hovering = $0 }
    }
}
