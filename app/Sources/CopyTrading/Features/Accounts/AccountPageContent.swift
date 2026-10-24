import DesktopCore
import SwiftUI

/// A read account's page: its name, then, when the page is wide enough, two columns: the money,
/// its curve and positions or activity on the left, and a side rail holding the calls waiting on the
/// owner and the limits the account trades under, so both stay in view beside the chart. On a
/// narrower page, or while a post shares the window, the same parts stack: the waiting calls first,
/// then the money and curve, the limits, and positions or activity.
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
    // The tab the owner last chose, kept across launches.
    @AppStorage("account.section") private var section = AccountSection.positions
    @State private var width: CGFloat = 0
    /// The call whose ticket or chart marker is under the pointer.
    @State private var highlightedCall: String?

    /// The rail needs room for a readable chart beside it.
    private static let railWidth: CGFloat = 300
    private static let wideEnough: CGFloat = 880

    private var isWide: Bool { !isSharingWidth && width >= Self.wideEnough }

    private var hasWarnings: Bool {
        !account.ownershipIncidents.isEmpty || AccountWarnings.shown(account.accountRiskReason) != nil
            || AccountWarnings.shown(account.accountActivityReason) != nil || !account.unresolvedIncidents.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            AccountPageHeader(account: account, model: model, feature: feature)
            if hasWarnings {
                VStack(alignment: .leading, spacing: 8) {
                    AccountWarnings(account: account, model: model, feature: feature)
                }
            }
            if isWide {
                HStack(alignment: .top, spacing: 36) {
                    VStack(alignment: .leading, spacing: 28) {
                        money(plotHeight: 240)
                        sections
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 28) {
                        needsYou(isCompact: true)
                        AccountFacts(account: account, policy: policy, isCompact: true, editLimits: editLimits)
                    }
                    .frame(width: Self.railWidth)
                }
            } else {
                needsYou(isCompact: isSharingWidth || width < 760)
                money(plotHeight: isSharingWidth ? 120 : 200)
                AccountFacts(account: account, policy: policy, isCompact: false, editLimits: editLimits)
                sections
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .onAppear {
            if account.positions.isEmpty { section = .activity }
        }
    }

    private func money(plotHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            AccountBalanceSummary(account: account, model: model, feature: feature)
            EquityChart(
                account: account,
                history: feature.histories[account.accountID],
                isRead: feature.historiesRead.contains(account.accountID),
                window: feature.historyWindow,
                chooseWindow: chooseWindow,
                plotHeight: plotHeight,
                callMarks: callMarks,
                highlightedCall: $highlightedCall
            )
        }
    }

    private func needsYou(isCompact: Bool) -> some View {
        AccountNeedsYou(
            accountID: account.accountID,
            activity: feature.knownActivity,
            directory: GuruDirectory(model.savedTradingConfiguration),
            skippedCalls: model.skippedCalls,
            canCopy: !feature.accounts.isEmpty,
            // While the account isn't copying, the header's Start Copying is the page's ink capsule.
            ownsPrimaryAction: CopyingState.account(account, processing: model.tradingStatus).isCopying,
            selectedPostID: selectedPostID,
            isCompact: isCompact,
            highlightedSourceID: $highlightedCall,
            copy: copy,
            open: { openPost($0.source.id) }
        )
    }

    /// Each waiting call pinned on the curve at the time it was posted.
    private var callMarks: [EquityCallMark] {
        AccountNeedsYou.waiting(
            accountID: account.accountID, activity: feature.knownActivity, skippedCalls: model.skippedCalls, now: .now
        ).compactMap { call in
            guard let at = Humanize.date(call.source.sourceAt) else { return nil }
            return EquityCallMark(
                id: call.source.sourceID, at: at,
                label: L10n.string("Call · %@", at.formatted(AppTime.style(.dateTime.hour().minute()))))
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionSwitcher(
                choices: AccountSection.allCases, selection: $section, title: \.title,
                count: { $0 == .positions ? account.positions.count { !PositionRow.isEmpty($0) } : 0 }, identifier: "account.section")
            switch section {
            case .positions:
                AccountPositions(account: account, model: model, feature: feature) { openPost($0.id) }
            case .activity:
                AccountFeedList(
                    accountID: account.accountID, model: model, feature: feature, selectedPostID: selectedPostID,
                    openPost: openPost)
            }
        }
    }

    private func copy(_ call: WaitingCall) {
        sheet = .manualReview(call.source, copying: call)
    }

    private func chooseWindow(_ window: EquityHistoryWindow) {
        Task { await feature.chooseHistoryWindow(window, for: account.accountID, using: model.accountActions()) }
    }

    /// The account's sheet opens over this page on its limits; the changes apply as soon as they
    /// are saved.
    private func editLimits() {
        model.editAccount(named: account.accountID, focus: .limits)
    }
}
