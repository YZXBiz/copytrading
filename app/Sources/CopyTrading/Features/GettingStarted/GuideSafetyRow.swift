import SwiftUI

/// One safety control in the guide: the control itself, drawn as it appears, beside what it does.
struct GuideSafetyRow<Control: View>: View {
    let text: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            control
                .frame(width: 180)
                .accessibilityHidden(true)
            Text(localizedMarkdown(text))
                .font(DesignTokens.documentBody)
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }
}
