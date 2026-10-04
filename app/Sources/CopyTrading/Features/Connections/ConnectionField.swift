import SwiftUI

/// A labelled entry in a connect sheet: a small grey label over a soft rounded field. A click
/// anywhere on the field's box puts the cursor in it.
struct ConnectionField<Field: View>: View {
    let label: String
    let focus: () -> Void
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(label))
                .font(DesignTokens.caption.weight(.medium))
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityHidden(true)
            field
                .textFieldStyle(.plain)
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Behind the field, so a click on the field itself reaches the field; a click on
                // the rest of the box still puts the cursor in it.
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.well)
                        .contentShape(.rect)
                        .onTapGesture(perform: focus)
                }
        }
    }
}
