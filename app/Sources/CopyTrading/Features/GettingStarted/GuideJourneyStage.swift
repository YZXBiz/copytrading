import SwiftUI

/// One stage of a post's journey under the diagram: its number and serif title, one sentence,
/// what the owner controls, and the one thing to keep in mind.
struct GuideJourneyStage: View {
    let number: Int
    let title: String
    let text: String
    let control: String
    let caution: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(number.formatted())
                    .font(.system(.body, design: .serif).italic().weight(.medium))
                    .foregroundStyle(Palette.accent)
                Text(L10n.string(title))
                    .font(.system(.title3, design: .serif).weight(.medium))
                    .foregroundStyle(Palette.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(localizedMarkdown(text))
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 3) {
                note(control, symbol: "slider.horizontal.3", tint: Palette.tertiaryInk)
                note(caution, symbol: "exclamationmark.circle", tint: .orange)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func note(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: symbol)
                .font(DesignTokens.caption)
                .foregroundStyle(tint)
                .frame(width: 13)
                .accessibilityHidden(true)
            Text(localizedMarkdown(text))
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
