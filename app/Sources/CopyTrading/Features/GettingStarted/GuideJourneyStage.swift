import SwiftUI

/// One stage of a post's journey in the guide: a numbered serif title, one sentence, what the
/// owner controls, the one thing to keep in mind, and a small picture of it drawn with real parts.
struct GuideJourneyStage<Figure: View>: View {
    let number: Int
    let title: String
    let text: String
    let control: String
    let caution: String
    let figureDescription: String
    @ViewBuilder let figure: Figure

    var body: some View {
        // The page keeps at least 300 points beside a figure, even at the smallest window.
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
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
                    .font(DesignTokens.documentBody)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    note(control, symbol: "slider.horizontal.3", tint: Palette.tertiaryInk)
                    note(caution, symbol: "exclamationmark.circle", tint: .orange)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            GuideFigure(description: L10n.string(figureDescription), showsWindowControls: false) { figure }
                .frame(width: 240)
        }
        .padding(.vertical, 22)
    }

    private func note(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(DesignTokens.caption)
                .foregroundStyle(tint)
                .frame(width: 14)
                .accessibilityHidden(true)
            Text(localizedMarkdown(text))
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
