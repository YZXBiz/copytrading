import SwiftUI

/// A title in two parts: the lead, then a quieter second line in regular weight and secondary ink.
/// Chinese reads as one phrase, so there the two parts run together on a single line.
struct TwoLineTitle: View {
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
                Text(emphasis)
                    .fontWeight(.regular)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("%@ %@", lead, emphasis))
        .accessibilityAddTraits(.isHeader)
    }
}
