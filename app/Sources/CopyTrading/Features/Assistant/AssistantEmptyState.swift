import SwiftUI

/// The panel before the first question: "Ask about / your trading" in the display face over the
/// walker's ground, then four questions to start with between hairlines, or, before a model is set
/// up, where to choose one.
struct AssistantEmptyState: View {
    let hasModel: Bool
    let suggestions: [String]
    let ask: (String) -> Void
    let openConnections: () -> Void
    @State private var hovered: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 28)
            greeting
                .padding(.horizontal, 24)
            Text(
                L10n.string(
                    hasModel
                        ? "Answers come from your own posts, accounts, and setup."
                        : "It answers with the model that reads your posts. Choose one in Connections to begin.")
            )
            .font(DesignTokens.lede)
            .tracking(DesignTokens.ledeTracking)
            .foregroundStyle(Palette.tertiaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
            .padding(.horizontal, 24)
            InkGround(height: 56)
                .overlay(alignment: .bottomTrailing) {
                    InkWalker()
                        .padding(.trailing, 64)
                        .padding(.bottom, 3)
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
            Group {
                if hasModel {
                    suggestionList
                } else {
                    noModel
                }
            }
            .padding(.top, hasModel ? 26 : 18)
            // Twice the room below as above, so the greeting sits a third of the way down.
            Spacer(minLength: 16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var greeting: some View {
        TwoLineTitle(lead: L10n.string("Ask about"), emphasis: L10n.string("your trading"))
            .font(DesignTokens.panelTitle)
            .foregroundStyle(Palette.ink)
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            Hairline()
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                if index > 0 {
                    Hairline()
                }
                Button {
                    ask(suggestion)
                } label: {
                    HStack(spacing: 12) {
                        Text(suggestion)
                            .font(DesignTokens.bodyText)
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(hovered == index ? Palette.ink : Palette.tertiaryInk)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 12)
                    .background(Palette.hover.opacity(hovered == index ? 0.4 : 0))
                    .contentShape(.rect)
                }
                .buttonStyle(QuietPressButtonStyle())
                .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
                .accessibilityLabel(suggestion)
                .accessibilityHint(L10n.string("Asks the assistant"))
                .accessibilityIdentifier("assistant.suggestion.\(index)")
            }
        }
        .overlay(alignment: .bottom) { Hairline() }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        .padding(.horizontal, 24)
    }

    private var noModel: some View {
        Button(L10n.string("Open Connections"), action: openConnections)
            .buttonStyle(PageButtonStyle())
            .padding(.horizontal, 24)
            .accessibilityHint(L10n.string("Shows where to choose the model"))
            .accessibilityIdentifier("assistant.openConnections")
    }
}
