import DesktopCore
import SwiftUI

/// One account as one page: who it is and whether it trades, its money and limits side by side,
/// its holdings, and its history, separated by hairlines rather than boxes.
struct AccountSection: View {
    @Environment(\.colorSchemeContrast) private var contrast

    let account: AccountOverview
    let policy: TradingAccountPolicy?
    let model: AppModel
    let feature: AccountFeatureModel

    private let surfacePadding: CGFloat = 24
    private let balanceMinWidth: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            AccountHeaderPanel(account: account, model: model, feature: feature)
            if !account.ownershipIncidents.isEmpty || account.accountRiskReason != nil
                || account.accountActivityReason != nil || !account.unresolvedIncidents.isEmpty
            {
                AccountWarnings(account: account)
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    AccountBalancePanel(account: account)
                        .frame(minWidth: balanceMinWidth, maxWidth: .infinity, alignment: .leading)
                    if let policy {
                        Divider()
                        AccountLimitsPanel(account: account, policy: policy)
                            .frame(width: 248)
                    }
                }
                VStack(alignment: .leading, spacing: 20) {
                    AccountBalancePanel(account: account)
                    if let policy {
                        Divider()
                        AccountLimitsPanel(account: account, policy: policy)
                    }
                }
            }
            Divider()
            PageSection("Positions", symbol: "square.stack.3d.up") {
                PositionsTable(
                    positions: account.positions,
                    accountID: account.accountID,
                    environment: account.environment,
                    gurus: GuruDirectory(model.savedTradingConfiguration),
                    activity: feature.activity,
                    openPost: openPost,
                    saleOperations: model.accountActions(),
                    confirmOwner: model.confirmOwner,
                    saleFinished: refreshAfterSale
                )
            }
            Divider()
            AccountEventsDisclosure(accountID: account.accountID, model: model, feature: feature)
        }
        .padding(surfacePadding)
        .background(Palette.page, in: .rect(cornerRadius: DesignTokens.readingCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.readingCornerRadius)
                .strokeBorder(contrast == .increased ? Palette.secondaryInk : Palette.hairline, lineWidth: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .shadow(color: .black.opacity(0.035), radius: 6, y: 2)
    }

    private func refreshAfterSale() {
        Task { await feature.refresh(using: model.accountActions()) }
    }

    private func openPost(_ post: SourceActivity) {
        feature.focusedActivityID = post.id
        model.selectedScreen = .activity
    }
}
