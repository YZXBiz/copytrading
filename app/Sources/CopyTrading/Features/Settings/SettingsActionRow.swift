import SwiftUI

/// A row that does something when clicked, such as "Stop Engine": the action
/// in ink, or red when it stops or removes something. What it does is a tooltip; a line under it
/// shows only a reading, such as how big the log is.
struct SettingsActionRow: View {
    let title: String
    /// What the action does, as a tooltip.
    var hint: String?
    /// A reading shown under the action.
    var detail: String?
    var role: ButtonRole?
    var identifier: String?
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            SettingsRow(title: title, detail: detail, titleColor: role == .destructive ? Palette.loss : Palette.ink)
                .background(Palette.ink.opacity(isHovered && isEnabled ? 0.04 : 0))
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(L10n.string(title))
        .help(hint.map { L10n.string($0) } ?? "")
        .accessibilityHint(hint.map { L10n.string($0) } ?? "")
        .accessibilityIdentifier(identifier ?? title)
    }
}
