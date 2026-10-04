import SwiftUI

/// The top of a connect sheet: one sentence on where the key comes from, a button that opens that
/// page, and the full steps a click away.
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
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                }
                Spacer(minLength: 4)
                HelpPopoverButton(title: "Step by step", articles: [article])
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent.opacity(0.08), in: .rect(cornerRadius: 16, style: .continuous))
    }
}
