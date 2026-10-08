import DesktopCore
import SwiftUI

/// What the account holds. The balance above says when prices were read.
struct AccountPositions: View {
    let account: AccountOverview
    let model: AppModel
    let feature: AccountFeatureModel
    let openPost: (SourceActivity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ListHeading("Positions")
            PositionsTable(
                positions: account.positions,
                accountID: account.accountID,
                environment: account.environment,
                approvesOrders: model.approvesOrders(accountID: account.accountID),
                gurus: GuruDirectory(model.savedTradingConfiguration),
                activity: feature.activity,
                openPost: openPost,
                saleOperations: model.accountActions(),
                confirmOwner: model.confirmOwner,
                saleFinished: refreshAfterSale
            )
        }
    }

    private func refreshAfterSale() {
        Task { await feature.refresh(using: model.accountActions()) }
    }
}
