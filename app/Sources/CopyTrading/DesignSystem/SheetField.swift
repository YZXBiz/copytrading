import SwiftUI

/// A field that takes a whole line, such as a name or a key: a small label above, then the field
/// on a single underline.
struct SheetField<Field: View>: View {
    let title: String
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .accessibilityHidden(true)
            field
                .labelsHidden()
                .underlineField()
        }
        .padding(.vertical, 10)
    }
}
