import DesktopCore
import SwiftUI

/// A saved account in the sidebar: its mark, name, Paper or Live, and its balance.
struct SidebarAccountRow: View {
    let account: TradingAccountConfiguration
    let model: AppModel
    let accountFeature: AccountFeatureModel

    private var screen: AppModel.Screen { .account(account.id) }
    private var isLive: Bool { account.environment == .live }
    private var equity: Decimal? {
        accountFeature.accounts.first { $0.accountID == account.id }?.balance.flatMap { Decimal(engine: $0.equity) }
    }

    var body: some View {
        SidebarEntityRow(
            title: account.id,
            detail: L10n.string(isLive ? "Live" : "Paper"),
            detailTint: isLive ? .orange : Palette.tertiaryInk,
            value: equity?.formatted(.currency(code: "USD")),
            identifier: screen.identifier,
            isSelected: model.selectedScreen == screen,
            select: select
        ) {
            SidebarAccountGlyph(environment: account.environment)
        }
    }

    private func select() {
        model.selectedScreen = screen
    }
}
