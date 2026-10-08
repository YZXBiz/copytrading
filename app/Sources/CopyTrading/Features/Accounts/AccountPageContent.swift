import DesktopCore
import SwiftUI

/// A read account's page, top to bottom: header, money and chart, limits, warnings, the calls
/// waiting on the owner, holdings, and activity.
struct AccountPageContent: View {
    let account: AccountOverview
    let policy: TradingAccountPolicy?
    let model: AppModel
    let feature: AccountFeatureModel
    let activityState: ActivityScreenState
    let isSharingWidth: Bool
    @Binding var sheet: ActivitySheet?

    private var hasWarnings: Bool {
        !account.ownershipIncidents.isEmpty || account.accountRiskReason != nil
            || account.accountActivityReason != nil || !account.unresolvedIncidents.isEmpty
    }

    var body: some View {
        let directory = GuruDirectory(model.savedTradingConfiguration)
        VStack(alignment: .leading, spacing: 24) {
            AccountPageHeader(account: account, model: model, feature: feature)
            AccountBalanceSummary(account: account, model: model, feature: feature)
            EquityChart(
                account: account,
                history: feature.histories[account.accountID],
                window: feature.historyWindow,
                chooseWindow: chooseWindow,
                plotHeight: isSharingWidth ? 120 : 176
            )
            if let policy {
                AccountLimitsStrip(account: account, policy: policy, isCompact: isSharingWidth, editLimits: editLimits)
            }
        }
        if hasWarnings {
            VStack(alignment: .leading, spacing: 8) {
                AccountWarnings(account: account, model: model, feature: feature)
            }
        }
        AccountNeedsYou(
            accountID: account.accountID,
            activity: feature.activity,
            directory: directory,
            skippedCalls: model.skippedCalls,
            canCopy: !feature.accounts.isEmpty,
            copy: copy
        )
        if !isSharingWidth {
            AccountPositions(account: account, model: model, feature: feature, openPost: openPost)
        }
        AccountActivityFeed(
            accountID: account.accountID,
            activity: feature.activity,
            directory: directory,
            selection: activityState.selectedActivityID
        )
    }

    private func copy(_ call: WaitingCall) {
        sheet = .manualReview(call.source, copying: call)
    }

    private func chooseWindow(_ window: EquityHistoryWindow) {
        Task { await feature.refreshHistories(window: window, using: model.accountActions()) }
    }

    /// The account's sheet opens over this page; the changes apply as soon as they are saved.
    private func editLimits() {
        model.editAccount(named: account.accountID)
    }

    private func openPost(_ post: SourceActivity) {
        activityState.focusActivity(post.id)
    }
}
