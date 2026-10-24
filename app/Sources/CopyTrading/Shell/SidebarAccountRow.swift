import DesktopCore
import SwiftUI

/// A saved account in the sidebar: its mark, name, Paper or Live with whether it copies, and its
/// balance, so two accounts read at a glance.
struct SidebarAccountRow: View {
    let account: TradingAccountConfiguration
    let model: AppModel
    let accountFeature: AccountFeatureModel

    private var screen: AppModel.Screen { .account(account.id) }
    private var isLive: Bool { account.environment == .live }
    private var overview: AccountOverview? { accountFeature.accounts.first { $0.accountID == account.id } }
    private var copying: CopyingState {
        overview.map { CopyingState.account($0, processing: model.tradingStatus) } ?? CopyingState(.notStarted)
    }
    private var isStopped: Bool { copying.word == .stopped }
    private var copyWord: String { copying.title }
    private var equity: Decimal? {
        accountFeature.accounts.first { $0.accountID == account.id }?.balance.flatMap { Decimal(engine: $0.equity) }
    }

    var body: some View {
        SidebarEntityRow(
            title: account.id,
            detail: L10n.string("%@ · %@", L10n.string(isLive ? "Live" : "Paper"), copyWord),
            detailTint: isStopped ? Palette.amber : isLive ? Palette.live : Palette.tertiaryInk,
            // Whole dollars, so the name keeps its room; the page itself shows the cents.
            value: equity?.formatted(.currency(code: "USD").precision(.fractionLength(0))),
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
