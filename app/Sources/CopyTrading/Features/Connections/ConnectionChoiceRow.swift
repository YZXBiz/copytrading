import SwiftUI

/// One option in a Connections panel: a bold name,
/// what it does, and a circled arrow.
struct ConnectionChoiceRow: View {
    let title: String
    let detail: String
    var identifier: String?
    /// A row in a long list: smaller type and less air, so a dozen fit in a panel.
    var compact = false
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(alignment: compact ? .center : .top, spacing: 16) {
                VStack(alignment: .leading, spacing: compact ? 1 : 3) {
                    Text(title)
                        .font(.system(.body, weight: .semibold).scaled(by: compact ? 14.0 / 13 : 15.0 / 13))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(compact ? DesignTokens.caption : .body)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: compact ? 15 : 17, weight: .light))
                    .foregroundStyle(isHovered ? Palette.ink : Palette.tertiaryInk)
                    .offset(x: isHovered && !reduceMotion ? 2 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, compact ? 8 : 13)
            .background(Palette.page.opacity(isHovered ? 0.55 : 0), in: .rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .accessibilityIdentifier(identifier ?? title)
    }
}
