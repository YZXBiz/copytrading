import DesktopCore
import SwiftUI

/// Today's change, the balance behind it, and the equity curve: the top of the Today page.
struct PortfolioPanel: View {
    @Bindable var model: AppModel
    let feature: AccountFeatureModel
    @Environment(\.colorSchemeContrast) private var contrast

    private var balances: [AccountBalance] {
        feature.accounts.filter(\.activeConfiguration).compactMap(\.balance)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            EquityChart(
                accounts: feature.accounts,
                histories: feature.histories,
                window: feature.historyWindow,
                chooseWindow: chooseWindow
            )
            Divider()
            TodaySummary(balances: balances, accountCount: feature.accounts.count)
        }
        .padding(DesignTokens.workingSurfacePadding)
        .background(Palette.page, in: .rect(cornerRadius: DesignTokens.readingCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.readingCornerRadius)
                .strokeBorder(contrast == .increased ? Palette.secondaryInk : Palette.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.035), radius: 6, y: 2)
    }

    private func chooseWindow(_ window: EquityHistoryWindow) {
        Task { await feature.refreshHistories(window: window, using: model.accountActions()) }
    }
}
