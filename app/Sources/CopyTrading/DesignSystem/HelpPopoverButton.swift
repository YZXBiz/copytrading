import SwiftUI

/// "Where do I find this?" beside a form section: the same steps the guide shows, one click away
/// from the field that needs them.
struct HelpPopoverButton: View {
    var title = "Where do I find this?"
    let articles: [HelpArticle]
    @State private var isPresented = false

    var body: some View {
        Button(L10n.string(title), systemImage: "questionmark.circle", action: toggle)
            .buttonStyle(.borderless)
            .font(DesignTokens.caption)
            .foregroundStyle(Palette.ink)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                FloatingPanelSurface(title: L10n.string(title)) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(articles) { article in
                                if article.id != articles.first?.id {
                                    Divider()
                                }
                                HelpArticleView(article: article)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: 480)
                }
                .frame(width: 400, alignment: .leading)
                .onExitCommand(perform: dismiss)
            }
    }

    private func toggle() {
        isPresented.toggle()
    }

    private func dismiss() {
        isPresented = false
    }
}
