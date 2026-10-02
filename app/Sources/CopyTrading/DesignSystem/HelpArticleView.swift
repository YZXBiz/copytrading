import SwiftUI

@MainActor
func localizedMarkdown(_ englishSourceText: String) -> AttributedString {
    let localized = L10n.string(englishSourceText)
    return (try? AttributedString(markdown: localized)) ?? AttributedString(localized)
}

/// One how-to as the guide and the popovers draw it: a title, numbered steps, then any caution
/// and the place to go.
struct HelpArticleView: View {
    let article: HelpArticle
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle {
                Text(localizedMarkdown(article.title))
                    .font(DesignTokens.sectionTitle)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            if let intro = article.intro {
                Text(localizedMarkdown(intro))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(article.steps.enumerated(), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        StepNumber(number: index + 1)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
                        Text(localizedMarkdown(step))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        L10n.string(
                            "Step %lld: %@", Int64(index + 1),
                            String(localizedMarkdown(step).characters)
                        )
                    )
                }
            }
            if let caution = article.caution {
                Callout(L10n.string(caution), tone: .caution)
            }
            if let destination = article.destination {
                Link(destination: destination.url) {
                    Label(L10n.string(destination.title), systemImage: "arrow.up.forward.square")
                }
                .help(destination.url.absoluteString)
            }
        }
        .font(DesignTokens.bodyText)
        .textSelection(.enabled)
    }
}
