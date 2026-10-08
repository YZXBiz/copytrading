import SwiftUI

/// The top of an editing sheet, in place of the window's small grey title: what the sheet edits in
/// tracked capitals, then its name in the display face.
/// Use it as the first section of the sheet's form.
struct SheetTitle: View {
    let kind: String
    let name: String

    var body: some View {
        Section {
        } header: {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(kind)
                Text(name)
                    .font(DesignTokens.panelTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
            .textCase(nil)
            .padding(.bottom, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.string("%@ %@", kind, name))
            .accessibilityAddTraits(.isHeader)
        }
    }
}
