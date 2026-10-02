import SwiftUI

/// A serif title in two parts: the lead, then an italic second line. Chinese has no italic and
/// reads as one phrase, so there the two parts run together on a single line.
struct SerifTitle: View {
    let lead: String
    let emphasis: String
    var alignment: HorizontalAlignment = .leading

    private var runsTogether: Bool { AppLanguagePreference.shared.language == .simplifiedChinese }

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            if runsTogether {
                Text(lead + emphasis)
            } else {
                Text(lead)
                Text(emphasis).italic()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("%@ %@", lead, emphasis))
        .accessibilityAddTraits(.isHeader)
    }
}
