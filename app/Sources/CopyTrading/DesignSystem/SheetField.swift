import SwiftUI

/// A row with a field to type in, such as a name or a key: its name and an optional line on what
/// it is for at the leading edge, the field at the trailing edge. Where the column is too narrow
/// for both, such as a Connections panel, `stacked` puts the name over a field the row's width.
struct SheetField<Field: View>: View {
    let title: String
    var hint: String?
    var stacked = false
    @ViewBuilder let field: Field

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignTokens.rowTitle)
                        .foregroundStyle(Palette.ink)
                        .accessibilityHidden(true)
                    if let hint {
                        Text(hint)
                            .font(DesignTokens.caption)
                            .foregroundStyle(Palette.tertiaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                field
                    .sheetInput(width: nil)
            }
            .padding(.vertical, 12)
        } else {
            SheetRow(title: title, hint: hint, labelsControl: true) {
                field
                    .sheetInput()
            }
        }
    }
}
