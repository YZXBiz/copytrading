import SwiftUI

/// One answer in a form row, as a plain word: the chosen one in ink, semibold, over a thin ink
/// underline; the rest tertiary. `detail` is a quiet word beside it, such as the dollars a size
/// buys. Butter is kept for the one choice the sheet turns on, so nothing here carries it.
struct FormChoice: View {
    let title: String
    var detail: String?
    var detailTint: Color?
    let isOn: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(title)
                    .font(DesignTokens.bodyText.weight(isOn ? .semibold : .regular))
                    .foregroundStyle(isOn || isHovered ? Palette.ink : Palette.tertiaryInk)
                    .padding(.bottom, 3)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Palette.ink).frame(height: 1.5).opacity(isOn ? 1 : 0)
                    }
                if let detail {
                    Text(detail)
                        .font(DesignTokens.caption)
                        .foregroundStyle(detailTint ?? Palette.tertiaryInk)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
