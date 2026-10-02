import DesktopCore
import SwiftUI

/// One idea as a card: a tinted page inside a white frame, a serif title,
/// a short line, and a picture. Clicking it opens the steps in a popover.
struct ConnectionIdeaCard: View {
    let idea: ConnectionIdea
    let provider: TradingProviderName
    /// Wide cards set the picture beside the words; narrow ones let it rise from the bottom edge.
    let isWide: Bool
    @State private var isPresented = false
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var article: HelpArticle { idea.article(for: provider) }

    var body: some View {
        Button(action: toggle) {
            ZStack(alignment: isWide ? .trailing : .bottomTrailing) {
                ConnectionIdeaFigure(idea: idea)
                    .offset(x: isWide ? -18 : 26, y: isWide ? 6 : 64)
                    .offset(y: isHovered && !reduceMotion ? -4 : 0)
                words
                    .padding(.trailing, isWide ? 220 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(22)
            }
            .frame(maxWidth: .infinity, minHeight: 196, maxHeight: 196)
            .background(idea.tint(dark: colorScheme == .dark), in: .rect(cornerRadius: 15))
            .clipShape(.rect(cornerRadius: 15))
            .padding(6)
            .background(Palette.page, in: .rect(cornerRadius: 21))
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: 21).strokeBorder(Palette.secondaryInk, lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(isHovered ? 0.1 : 0.05), radius: isHovered ? 14 : 8, y: isHovered ? 6 : 3)
            .contentShape(.rect(cornerRadius: 21))
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: isHovered)
        .accessibilityLabel(idea.title)
        .accessibilityHint(idea.blurb)
        .accessibilityIdentifier("connections.idea.\(idea.rawValue)")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            FloatingPanelSurface(title: article.title) {
                HelpArticleView(article: article, showsTitle: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 400, alignment: .leading)
            .onExitCommand(perform: dismiss)
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(idea.title)
                .font(DesignTokens.cardSerif)
                .foregroundStyle(Palette.ink)
            Text(idea.blurb)
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(isWide ? 4 : 3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggle() {
        isPresented.toggle()
    }

    private func dismiss() {
        isPresented = false
    }
}
