import SwiftUI

/// One answer among a few, as plain words in a row, with no box: tracked capitals, or the display
/// face for the one choice a sheet turns on (buy or sell). The chosen one is in ink with the butter
/// marker behind it; the rest are tertiary. `detail` is a quiet line under it, such as the shares
/// and value a held stock is worth.
struct ChoiceWord: View {
    let title: String
    var detail: String?
    /// The detail's colour, for the few words colour carries: Live in orange.
    var detailTint: Color?
    var large = false
    let isOn: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if large {
                        Text(title)
                            .font(DisplayFont.font(size: 30, weight: .medium, relativeTo: .title))
                    } else {
                        Text(title.uppercased())
                            .font(DesignTokens.bodyEmphasis.weight(.semibold))
                            .tracking(DesignTokens.eyebrowTracking)
                    }
                }
                .monospacedDigit()
                .foregroundStyle(isOn || isHovered ? Palette.ink : Palette.tertiaryInk)
                .markerHighlight(isOn)
                if let detail {
                    Text(detail)
                        .font(DesignTokens.caption)
                        .monospacedDigit()
                        .foregroundStyle(detailTint ?? (isOn ? Palette.secondaryInk : Palette.tertiaryInk))
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
