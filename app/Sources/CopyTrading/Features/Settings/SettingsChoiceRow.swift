import SwiftUI

/// One of several choices in a well, ticked when chosen, as a radio group.
struct SettingsChoiceRow: View {
    let title: String
    var detail: String?
    let isSelected: Bool
    let choose: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: choose) {
            SettingsRow(title: title, detail: detail) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .background(Palette.ink.opacity(isHovered ? 0.04 : 0))
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(L10n.string(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
