import SwiftUI

/// One line of a form: its label on the left in a fixed column, its choices on the right, and an
/// optional quiet note under the choices.
struct FormRow<Content: View>: View {
    let label: String
    var note: String?
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.tertiaryInk)
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
    }
}
