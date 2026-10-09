import DesktopCore
import SwiftUI

/// A read account's page: a hero (name, balance, the curve, what the balance is
/// made of), any warnings, the calls waiting on the owner, then positions, activity, or limits,
/// one at a time.
struct AccountPageContent: View {
    let account: AccountOverview
    let policy: TradingAccountPolicy?
    let model: AppModel
    let feature: AccountFeatureModel
    let isSharingWidth: Bool
    /// The post open beside the page, which its row shows as chosen.
    let selectedPostID: SourceActivity.ID?
    @Binding var sheet: ActivitySheet?
    let openPost: (SourceActivity.ID) -> Void
    @State private var section = AccountSection.positions

    private var hasWarnings: Bool {
        !account.ownershipIncidents.isEmpty || account.accountRiskReason != nil
            || account.accountActivityReason != nil || !account.unresolvedIncidents.isEmpty
    }

    var body: some View {
        let directory = GuruDirectory(model.savedTradingConfiguration)
        VStack(alignment: .leading, spacing: 28) {
            AccountPageHeader(account: account, model: model, feature: feature)
            AccountBalanceSummary(account: account, model: model, feature: feature)
            EquityChart(
                account: account,
                history: feature.histories[account.accountID],
                window: feature.historyWindow,
                chooseWindow: chooseWindow,
                plotHeight: isSharingWidth ? 120 : 200
            )
            AccountBalanceBreakdown(account: account, model: model, feature: feature)
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
            selectedPostID: selectedPostID,
            copy: copy,
            open: { openPost($0.source.id) }
        )
        VStack(alignment: .leading, spacing: 20) {
            TrackedSwitcher(
                choices: AccountSection.allCases, selection: $section, title: \.title,
                count: { $0 == .positions ? account.positions.count { !PositionRow.isEmpty($0) } : 0 }, identifier: "account.section")
            switch section {
            case .positions:
                AccountPositions(account: account, model: model, feature: feature) { openPost($0.id) }
            case .activity:
                AccountFeedList(
                    accountID: account.accountID, model: model, feature: feature, selectedPostID: selectedPostID,
                    openPost: openPost)
            case .limits:
                if let policy {
                    AccountLimitsStrip(account: account, policy: policy, isCompact: isSharingWidth, editLimits: editLimits)
                }
            }
        }
        .onAppear {
            if account.positions.isEmpty { section = .activity }
        }
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
}
