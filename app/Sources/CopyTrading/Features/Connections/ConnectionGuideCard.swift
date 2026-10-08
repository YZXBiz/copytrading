import SwiftUI

/// The top of a connect sheet, on the page with a hairline under it: one sentence on where the key
/// comes from, a button that opens that page, and the full steps a click away.
struct ConnectionGuideCard: View {
    let article: HelpArticle
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let intro = article.intro {
                Text(localizedMarkdown(intro))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if let destination = article.destination {
                    Button(L10n.string(destination.title)) { openURL(destination.url) }
                        .buttonStyle(PageButtonStyle())
                }
                Spacer(minLength: 4)
                HelpPopoverButton(title: "Step by step", articles: [article])
            }
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
    }
}
