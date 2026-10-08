import SwiftUI

/// A first-run page that invites you in instead of showing an empty pane: a framed card with a
/// small drawing of what will appear here on the app's chart paper, a title with a quieter
/// second line, one plain sentence, and what to do next.
struct InvitationCard<Figure: View, Actions: View>: View {
    let lead: String
    let emphasis: String
    let message: String
    @ViewBuilder let figure: Figure
    @ViewBuilder let actions: Actions
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            figure
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .background { ChartPaperBackdrop(focus: UnitPoint(x: 0.5, y: 0.55), gridSpacing: 22) }
                .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                TwoLineTitle(lead: L10n.string(lead), emphasis: L10n.string(emphasis))
                    .font(DesignTokens.panelTitle)
                    .foregroundStyle(Palette.ink)
                Text(L10n.string(message))
                    .font(DesignTokens.documentBody)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                actions
                    .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.panel, in: .rect(cornerRadius: 16, style: .continuous))
        .padding(6)
        .background(Palette.page, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(contrast == .increased ? Palette.secondaryInk : .black.opacity(0.05), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 16, y: 5)
        .frame(maxWidth: 620)
    }
}
