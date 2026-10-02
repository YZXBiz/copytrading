import SwiftUI

/// A labelled entry in a Connections panel, written like a settings row: a small grey label
/// over the value, typed in place. A click anywhere on the row puts the cursor in its field.
struct ConnectionField<Field: View>: View {
    let label: String
    let focus: () -> Void
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string(label))
                .font(DesignTokens.caption.weight(.medium))
                .foregroundStyle(Palette.tertiaryInk)
                .accessibilityHidden(true)
            field
                .textFieldStyle(.plain)
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .onTapGesture(perform: focus)
    }
}
