import SwiftUI

/// A row in a sheet's group whose answer is a few options that wrap: its name in a fixed column at
/// the leading edge, the options beside it, and an optional quiet note under them.
struct FormRow<Content: View>: View {
    let label: String
    var note: String?
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .font(DesignTokens.rowTitle)
                .foregroundStyle(Palette.ink)
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                content
                if let note {
                    Text(note)
                        .font(DesignTokens.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.tertiaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 48)
    }
}
