import SwiftUI

/// A sidebar row: a grey symbol, graphite text, and, when chosen, a light
/// grey pill. Never the accent: selection is a place, not an alarm. Screens and Settings pages
/// both list this way.
struct SidebarRow: View {
    let title: String
    let symbol: String
    let identifier: String
    let isSelected: Bool
    var badge = 0
    /// How far setup has come, shown as a small ring on Getting Started until it is done.
    var progress: Double?
    let select: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(L10n.string(title))
                    .font(DesignTokens.sidebarTitle.weight(.regular))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 4)
                if badge > 0 {
                    Text(badge.formatted())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.tertiaryInk)
                        .monospacedDigit()
                }
                if let progress {
                    ProgressRing(progress: progress, size: 14, lineWidth: 2)
                        .accessibilityHidden(true)
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
        .accessibilityIdentifier(identifier)
        // The label names the row; what changes (waiting items, setup progress) is its value.
        .accessibilityLabel(L10n.string(title))
        .accessibilityValue(accessibilityState)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityState: String {
        if badge > 0 { return L10n.string("%lld waiting", Int64(badge)) }
        return progress.map { L10n.string("%@ done", $0.formatted(.percent.precision(.fractionLength(0)))) } ?? ""
    }
}
