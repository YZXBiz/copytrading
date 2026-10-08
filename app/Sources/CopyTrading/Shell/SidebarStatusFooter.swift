import SwiftUI

/// The pages that set things up, under a hairline, and the always-visible answer to "is it
/// copying?", with Diagnostics one click from it.
struct SidebarStatusFooter: View {
    let model: AppModel

    private static let pages: [AppModel.Screen] = [.connections, .gettingStarted, .settings]

    @MainActor private var summary: (text: String, tone: StatusTone) {
        if model.runtimeState == .stopped || model.runtimeState == .failed {
            return (L10n.string("Engine stopped"), StatusTone(model.runtimeState))
        }
        guard model.savedTradingConfiguration != nil else { return (L10n.string("Not set up yet"), .inactive) }
        return CopyingSummary.of(model.tradingStatus)
    }

    @MainActor private var helpText: String {
        let count = model.tradingStatus?.activeAccounts ?? 0
        return model.tradingStatus?.state == .running
            ? L10n.string("Copying new posts into %@", Humanize.count(count, "account"))
            : summary.text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Hairline()
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            ForEach(Self.pages, id: \.self) { screen in
                SidebarRow(
                    title: screen.title,
                    symbol: screen.symbol,
                    identifier: screen.identifier,
                    isSelected: model.selectedScreen == screen,
                    progress: progress(for: screen)
                ) { model.selectedScreen = screen }
            }
            .padding(.horizontal, 10)
            HStack(spacing: 6) {
                Circle()
                    .fill(summary.tone.color)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(summary.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(L10n.string("Diagnostics"), systemImage: AppModel.Screen.diagnostics.symbol) {
                    model.selectedScreen = .diagnostics
                }
                .labelStyle(.iconOnly)
                .buttonStyle(QuietPressButtonStyle())
                .foregroundStyle(model.selectedScreen == .diagnostics ? Palette.accent : Palette.tertiaryInk)
                .help(L10n.string("Diagnostics"))
                .accessibilityIdentifier(AppModel.Screen.diagnostics.identifier)
            }
            .font(DesignTokens.sidebarDetail)
            .foregroundStyle(Palette.tertiaryInk)
            .help(helpText)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.string("Status: %@", summary.text))
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
    }

    /// Getting Started shows its ring only until the first setup is saved.
    private func progress(for screen: AppModel.Screen) -> Double? {
        guard screen == .gettingStarted, model.savedTradingConfiguration == nil else { return nil }
        return model.setupProgress.fraction
    }
}
