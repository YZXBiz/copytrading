import SwiftUI

/// A row with a field to type in, such as a name or a key: its name and an optional line on what
/// it is for at the leading edge, the field at the trailing edge.
struct SheetField<Field: View>: View {
    let title: String
    var hint: String?
    @ViewBuilder let field: Field

    var body: some View {
        SheetRow(title: title, hint: hint, labelsControl: true) {
            field
                .sheetInput()
        }
    }
}
