import DesktopCore
import SwiftUI

/// "Setup Tips", closing the Connections page: a serif heading with a
/// dismiss button and the how-tos as cards, wide and narrow in turn. Narrow pages stack them.
struct ConnectionIdeasSection: View {
    let provider: TradingProviderName
    let hide: () -> Void
    @State private var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("Setup Tips"))
                    .font(DesignTokens.displaySerif)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                Button(L10n.string("Hide Ideas"), systemImage: "xmark.circle.fill", action: hide)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.tertiaryInk.opacity(0.6))
                    .help(L10n.string("Hide Ideas"))
                    .accessibilityIdentifier("connections.hideIdeas")
            }
            if isCompact {
                ForEach(ConnectionIdea.allCases) { idea in
                    ConnectionIdeaCard(idea: idea, provider: provider, isWide: true)
                }
            } else {
                HStack(spacing: 18) {
                    ConnectionIdeaCard(idea: .channelID, provider: provider, isWide: true)
                    ConnectionIdeaCard(idea: .discordToken, provider: provider, isWide: false)
                        .frame(width: 300)
                }
                HStack(spacing: 18) {
                    ConnectionIdeaCard(idea: .interpreterKey, provider: provider, isWide: false)
                        .frame(width: 300)
                    ConnectionIdeaCard(idea: .telegram, provider: provider, isWide: true)
                }
            }
        }
        .onGeometryChange(for: Bool.self) {
            $0.size.width < 780
        } action: {
            isCompact = $0
        }
    }
}
