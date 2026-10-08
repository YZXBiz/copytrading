import DesktopCore
import SwiftUI

/// "Setup Tips", closing the Connections page: a heading with a dismiss button and the how-tos as
/// numbered notes, two to a row, set apart by hairlines. Narrow pages stack them.
struct ConnectionIdeasSection: View {
    let provider: TradingProviderName
    let hide: () -> Void
    @State private var isCompact = false

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 40, alignment: .top), count: isCompact ? 1 : 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("Setup Tips"))
                    .font(DesignTokens.displayTitle)
                    .tracking(DesignTokens.listHeadingTracking)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                Button(L10n.string("Hide Ideas"), systemImage: "xmark", action: hide)
                    .labelStyle(.iconOnly)
                    .buttonStyle(PageButtonStyle(horizontalPadding: 8))
                    .help(L10n.string("Hide Ideas"))
                    .accessibilityIdentifier("connections.hideIdeas")
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 32) {
                ForEach(Array(ConnectionIdea.allCases.enumerated()), id: \.element) { index, idea in
                    ConnectionIdeaCard(idea: idea, number: index + 1, provider: provider)
                }
            }
        }
        .onGeometryChange(for: Bool.self) {
            $0.size.width < 640
        } action: {
            isCompact = $0
        }
    }
}
