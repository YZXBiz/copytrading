import SwiftUI

/// The panel before the first question: "Ask about / *your trading*" in the invitations' serif,
/// then four questions to start with, or, before a model is set up, where to choose one.
struct AssistantEmptyState: View {
    let hasModel: Bool
    let suggestions: [String]
    let ask: (String) -> Void
    let openConnections: () -> Void
    @State private var hovered: Int?
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)
            greeting
            Text(
                L10n.string(
                    hasModel
                        ? "Answers come from your own posts, accounts, and setup."
                        : "It answers with the model that reads your posts. Choose one in Connections to begin.")
            )
            .font(DesignTokens.bodyText)
            .foregroundStyle(Palette.tertiaryInk)
            .multilineTextAlignment(.center)
            .padding(.top, 12)
            .padding(.horizontal, 32)
            Group {
                if hasModel {
                    suggestionList
                } else {
                    noModel
                }
            }
            .padding(.top, hasModel ? 30 : 18)
            // Twice the room below as above, so the greeting sits a third of the way down.
            Spacer(minLength: 16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var greeting: some View {
        SerifTitle(lead: L10n.string("Ask about"), emphasis: L10n.string("your trading"), alignment: .center)
            .font(DesignTokens.panelSerif)
            .foregroundStyle(Palette.secondaryInk)
            .multilineTextAlignment(.center)
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                if index > 0 {
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)
                        .padding(.leading, 16)
                        .accessibilityHidden(true)
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Palette.hover.opacity(hovered == index ? 0.6 : 0))
                    .contentShape(.rect)
                }
                .buttonStyle(QuietPressButtonStyle())
                .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
                .accessibilityLabel(suggestion)
                .accessibilityHint(L10n.string("Asks the assistant"))
                .accessibilityIdentifier("assistant.suggestion.\(index)")
            }
        }
        .background(Palette.page, in: .rect(cornerRadius: 14, style: .continuous))
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(contrast == .increased ? Palette.secondaryInk : Palette.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        .padding(.horizontal, 20)
    }

    private var noModel: some View {
        Button(action: openConnections) {
            InlineActionMark(title: "Open Connections")
        }
        .buttonStyle(QuietPressButtonStyle())
        .accessibilityHint(L10n.string("Shows where to choose the model"))
        .accessibilityIdentifier("assistant.openConnections")
    }
}
