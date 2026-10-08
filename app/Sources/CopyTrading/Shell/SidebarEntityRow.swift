import SwiftUI

/// An account or a guru in the sidebar: its mark, its name over one quiet line, and, for an
/// account, its balance at the trailing edge. Selection is a light grey pill, never the accent.
struct SidebarEntityRow<Leading: View>: View {
    let title: String
    let detail: String
    var detailTint: Color = Palette.tertiaryInk
    var value: String?
    let identifier: String
    let isSelected: Bool
    let select: () -> Void
    @ViewBuilder let leading: Leading
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                leading
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(DesignTokens.sidebarTitle.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail)
                        .font(DesignTokens.sidebarDetail)
                        .foregroundStyle(detailTint)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let value {
                    Text(value)
                        .font(DesignTokens.sidebarDetail.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([detail, value].compactMap(\.self).joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }
}
