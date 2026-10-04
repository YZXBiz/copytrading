import SwiftUI

/// The top of an editing sheet, in place of the window's small grey title: what the sheet edits in
/// serif, then its name in serif italic. Chinese has no italic, so there the name stays upright.
/// Use it as the first section of the sheet's form.
struct SheetTitle: View {
    let kind: String
    let name: String

    private var italic: Bool { AppLanguagePreference.shared.language != .simplifiedChinese }

    var body: some View {
        Section {
        } header: {
            VStack(alignment: .leading, spacing: 0) {
                Text(kind)
                    .foregroundStyle(Palette.secondaryInk)
                Text(name)
                    .italic(italic)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
            .font(DesignTokens.pageTitle)
            .textCase(nil)
            .padding(.bottom, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.string("%@ %@", kind, name))
            .accessibilityAddTraits(.isHeader)
        }
    }
}
