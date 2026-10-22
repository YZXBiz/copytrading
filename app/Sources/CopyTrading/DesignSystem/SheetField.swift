import SwiftUI

/// A field that takes a whole line, such as a name or a key: a small label above, then the field in
/// a soft well, so it reads as something to type in at a glance.
struct SheetField<Field: View>: View {
    let title: String
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .accessibilityHidden(true)
            field
                .labelsHidden()
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.well, in: .rect(cornerRadius: 8))
        }
        .padding(.vertical, 10)
    }
}
