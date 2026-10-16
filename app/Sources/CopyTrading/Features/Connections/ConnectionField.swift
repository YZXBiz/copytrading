import SwiftUI

/// A labelled entry in a connect panel, as every sheet writes one: a small grey label over the
/// field on its writing line, dotted at rest and ink while typing. No box.
struct ConnectionField<Field: View>: View {
    let label: String
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.string(label))
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .accessibilityHidden(true)
            field
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .underlineField()
        }
    }
}
