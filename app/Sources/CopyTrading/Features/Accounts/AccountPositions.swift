import DesktopCore
import SwiftUI

/// What the account holds, under a heading that says when its prices were read.
struct AccountPositions: View {
    let account: AccountOverview
    let model: AppModel
    let feature: AccountFeatureModel
    let openPost: (SourceActivity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ListHeading("Positions") {
                if let observedAt = account.balance?.observedAt {
                    AccountFreshness(
                        observedAt: observedAt, isRefreshing: false,
                        engineStopped: model.runtimeState == .stopped || model.runtimeState == .failed,
                        refresh: {}, compact: true)
                }
            }
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
