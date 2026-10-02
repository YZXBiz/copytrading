import SwiftUI

/// A row that does something when clicked, such as "Stop Engine": the action
/// in the accent, or red when it stops or removes something, with what it does underneath.
struct SettingsActionRow: View {
    let title: String
    var detail: String?
    var role: ButtonRole?
    var identifier: String?
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            SettingsRow(title: title, detail: detail, titleColor: role == .destructive ? .red : Palette.accent)
                .background(Palette.ink.opacity(isHovered && isEnabled ? 0.04 : 0))
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(L10n.string(title))
        .accessibilityHint(detail.map { L10n.string($0) } ?? "")
        .accessibilityIdentifier(identifier ?? title)
    }
}
