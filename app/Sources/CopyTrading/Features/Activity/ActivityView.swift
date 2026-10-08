import DesktopCore
import SwiftUI

struct ActivityView: View {
    let model: AppModel
    let feature: AccountFeatureModel
    @Bindable var screenState: ActivityScreenState
    @State private var reviewFeature = ManualReviewFeatureModel()
    @State private var selectedSheet: ActivitySheet?

    private var visibleActivity: [SourceActivity] {
        feature.activity.filter { screenState.filter.includes($0, skipped: model.skippedCalls) }
    }

    private var selectedItem: SourceActivity? {
        visibleActivity.first { $0.id == screenState.selectedActivityID }
    }

    private var directory: GuruDirectory { GuruDirectory(model.savedTradingConfiguration) }

    /// No post has arrived yet, so the page invites instead of showing an empty list and pane.
    private var hasNoPosts: Bool {
        feature.activity.isEmpty && !feature.isRefreshing
    }

    var body: some View {
        Group {
            if hasNoPosts {
                ScrollView {
                    ActivityInvitation(model: model)
                        .padding(.horizontal, DesignTokens.pagePadding)
                        .padding(.top, 28)
                        .padding(.bottom, 32)
                }
            } else {
                readingLayout
            }
        }
        .pageBar {
            VStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) {
                        title
                        Spacer(minLength: 12)
                        filters
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        title
                        filters
                    }
                }
                .padding(.horizontal, DesignTokens.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 12)
                Divider()
                ActivityAlerts(feature: feature, setup: model.savedTradingConfiguration)
            }
        }
        .navigationTitle(L10n.string("Activity"))
        .task {
            prepareForDisplay()
        }
        .onChange(of: screenState.filter) { _, filter in
            screenState.applyFilter(
                filter, visibleIDs: feature.activity.filter { filter.includes($0, skipped: model.skippedCalls) }.map(\.id))
        }
        .onChange(of: feature.activity) {
            screenState.reconcileSelection(visibleIDs: visibleActivity.map(\.id))
        }
        .sheet(item: $selectedSheet, onDismiss: reviewFeature.clearPrivateEvidence) { selected in
            sheet(for: selected)
        }
    }

    /// The post list beside the reading pane.
    private var readingLayout: some View {
        HStack(spacing: 0) {
            ActivityListView(
                items: visibleActivity,
                directory: directory,
                selection: $screenState.selectedActivityID,
                filter: $screenState.filter,
                hasMore: feature.nextActivityCursor != nil,
                loadMore: loadMore
            )
            .frame(minWidth: 300, idealWidth: 320, maxWidth: 320)

            Divider()

            Group {
                if let selectedItem {
                    ActivityDetailView(
                        item: selectedItem,
                        guruName: directory.name(for: selectedItem.guruID),
                        canReview: !feature.accounts.isEmpty,
                        canEvaluate: model.savedTradingConfiguration?.routes.isEmpty == false,
                        skippedCalls: model.skippedCalls,
                        review: { selectedSheet = .manualReview(selectedItem, copying: nil) },
                        copy: { selectedSheet = .manualReview(selectedItem, copying: $0) },
                        evaluate: { selectedSheet = .historicalEvaluation(selectedItem) },
                        reviewHoldings: { accountID in
                            model.requestedAccountID = accountID
                            model.selectedScreen = .accounts
                        },
                        resume: ResumeWait(
                            selectedItem, waiting: ResumeWait.waitingAccounts(feature.accounts),
                            signalAge: ResumeWait.signalAge(in: model.savedTradingConfiguration)),
                        resumeEntries: { accountID in
                            let environment = feature.accounts.first { $0.accountID == accountID }?.environment
                            Task { await model.resumeEntries(accountID: accountID, environment: environment, feature: feature) }
                        }
                    )
                } else {
                    ActivityPlaceholderView(isRefreshing: feature.isRefreshing)
                }
            }
            .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func sheet(for selected: ActivitySheet) -> some View {
        switch selected {
        case .manualReview(let source, let copying):
            ManualReviewSheet(
                source: source,
                copying: copying,
                accounts: feature.accounts,
                operations: model.accountActions(),
                feature: reviewFeature,
                confirmOrders: { try await model.confirmOrders(for: $0, reason: L10n.string("send these orders")) },
                engineStopped: model.runtimeState == .stopped || model.runtimeState == .failed,
                startEngine: model.requestStart
            )
        case .historicalEvaluation(let source):
            HistoricalProfileEvaluationSheet(source: source, model: model)
        }
    }

    private var title: some View {
        Text(L10n.string("Activity"))
            .font(DesignTokens.pageTitle)
            .foregroundStyle(Palette.ink)
            .accessibilityAddTraits(.isHeader)
            .frame(minHeight: 30)
    }

    private var filters: some View {
        ActivityFilterBar(
            filter: filterBinding, activity: feature.activity, shown: visibleActivity.count,
            hasMore: feature.nextActivityCursor != nil
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private func loadMore() {
        Task { await feature.loadMore(using: model.accountActions()) }
    }

    private func prepareForDisplay() {
        if let focused = feature.focusedActivityID {
            screenState.focusActivity(focused)
            feature.focusedActivityID = nil
        } else {
            screenState.reconcileSelection(visibleIDs: visibleActivity.map(\.id))
        }
    }

    private var filterBinding: Binding<ActivityFilter> {
        Binding(
            get: { screenState.filter },
            set: { chosen in
                screenState.applyFilter(
                    chosen, visibleIDs: feature.activity.filter { chosen.includes($0, skipped: model.skippedCalls) }.map(\.id))
            }
        )
    }
}
