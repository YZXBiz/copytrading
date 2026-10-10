import DesktopCore
import SwiftUI

/// One idea as a plain note: a tracked number, a title, a short line, and "Show
/// Steps", which opens the steps in a popover.
struct ConnectionIdeaCard: View {
    let idea: ConnectionIdea
    let number: Int
    let provider: TradingProviderName
    @State private var isPresented = false
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var article: HelpArticle { idea.article(for: provider) }

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(String(format: "%02d", number))
                Text(idea.title)
                    .font(DesignTokens.cardTitle)
                    .tracking(DesignTokens.listHeadingTracking)
                    .foregroundStyle(Palette.ink)
                Text(idea.blurb)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Text(L10n.string("Show Steps"))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .offset(x: isHovered && !reduceMotion ? 3 : 0)
                }
                .font(DesignTokens.caption.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isHovered)
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

    private func toggle() {
        isPresented.toggle()
    }

    private func dismiss() {
        isPresented = false
    }
}
