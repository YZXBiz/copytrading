import SwiftUI

/// One answer among a few that don't fit a segmented control, such as the sizes a buy can take or
/// the prices it can pay: a bordered option the height of every sheet control, the chosen one
/// outlined in ink with its words in ink, the rest hairline-bordered and grey. `detail` sits beside
/// the title in the same option, such as the dollars a size buys.
struct FormChoice: View {
    let title: String
    var detail: String?
    var detailTint: Color?
    let isOn: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(title)
                    .font(DesignTokens.bodyText.weight(isOn ? .semibold : .regular))
                    .foregroundStyle(isOn || isHovered ? Palette.ink : Palette.secondaryInk)
                if let detail {
                    Text(detail)
                        .font(DesignTokens.caption)
                        .foregroundStyle(detailTint ?? Palette.tertiaryInk)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(isOn ? Palette.well : Palette.page, in: .rect(cornerRadius: DesignTokens.sheetControlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.sheetControlRadius)
                    .strokeBorder(isOn ? Palette.ink : Palette.hairline, lineWidth: isOn ? 1.5 : 1)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
