import SwiftUI

/// An account or a guru in the sidebar: one line with its mark, its name, and at the trailing
/// edge an account's balance or the calls a guru has waiting. Nothing under the name: a stopped
/// account shows an amber dot and a waiting count is amber, the only colour in the list; the rest
/// is said to VoiceOver. Selection is a light grey pill, never the accent.
struct SidebarEntityRow<Leading: View>: View {
    let title: String
    /// What VoiceOver reads after the name, the words the row leaves out.
    let spoken: String
    var value: String?
    /// Calls waiting on the owner, shown as an amber count.
    var count = 0
    /// Something is wrong (the account stopped copying), shown as an amber dot.
    var isAlerting = false
    let identifier: String
    let isSelected: Bool
    let select: () -> Void
    @ViewBuilder let leading: Leading
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                leading
                Text(title)
                    .font(DesignTokens.sidebarTitle.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if isAlerting {
                    Circle().fill(Palette.amber).frame(width: 6, height: 6)
                }
                if count > 0 {
                    Text(count.formatted())
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.amber)
                }
                if let value {
                    // Money is never cut short; the name gives way instead.
                    Text(value)
                        .font(DesignTokens.sidebarDetail.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                isSelected ? Palette.sidebarSelection : isHovering ? Palette.hover : .clear,
                in: .rect(cornerRadius: 8)
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
            .animation(nil, value: isSelected)
            .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
        .accessibilityValue([spoken, value].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }
}
