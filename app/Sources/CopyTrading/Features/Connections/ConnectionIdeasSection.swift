import DesktopCore
import SwiftUI

/// "Setup Tips", closing the Connections page: a heading with a dismiss button and the how-tos as
/// numbered notes, two to a row, set apart by space. Narrow pages stack them. Four notes need no
/// lazy grid, so all of them are built at once and VoiceOver reaches them without scrolling.
struct ConnectionIdeasSection: View {
    let provider: TradingProviderName
    let hide: () -> Void
    @State private var isCompact = false

    private var rows: [[(index: Int, idea: ConnectionIdea)]] {
        let ideas = Array(ConnectionIdea.allCases.enumerated()).map { (index: $0.offset, idea: $0.element) }
        let perRow = isCompact ? 1 : 2
        return stride(from: 0, to: ideas.count, by: perRow).map { Array(ideas[$0..<min($0 + perRow, ideas.count)]) }
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
            Grid(alignment: .topLeading, horizontalSpacing: 40, verticalSpacing: 32) {
                ForEach(rows, id: \.first?.idea) { row in
                    GridRow {
                        ForEach(row, id: \.idea) { item in
                            ConnectionIdeaCard(idea: item.idea, number: item.index + 1, provider: provider)
                        }
                    }
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
