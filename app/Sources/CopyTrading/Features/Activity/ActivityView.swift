import DesktopCore
import SwiftUI

struct ActivityView: View {
    let model: AppModel
    let feature: AccountFeatureModel
    @Bindable var screenState: ActivityScreenState
    @State private var reviewFeature = ManualReviewFeatureModel()
    @State private var selectedSheet: ActivitySheet?

    private var visibleActivity: [SourceActivity] {
        feature.activity.filter { screenState.includes($0) && screenState.filter.includes($0, skipped: model.skippedCalls) }
    }

    /// Posts in the chosen account, before the tab narrows them; the tabs count these.
    private var scopedActivity: [SourceActivity] {
        feature.activity.filter(screenState.includes)
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
                    HStack(alignment: .center, spacing: 24) {
                        heading
                        Spacer(minLength: 12)
                        controls
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        heading
                        controls
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
        .onChange(of: screenState.filter) { _, _ in
            screenState.reconcileSelection(visibleIDs: visibleActivity.map(\.id))
        }
        .onChange(of: screenState.accountID) { _, _ in
            screenState.reconcileSelection(visibleIDs: visibleActivity.map(\.id))
        }
        .onChange(of: feature.activity) {
            screenState.reconcileSelection(visibleIDs: visibleActivity.map(\.id))
        }
        .sheet(item: $selectedSheet, onDismiss: reviewFeature.clearPrivateEvidence) { selected in
            ActivitySheetContent(selected: selected, model: model, feature: feature, reviewFeature: reviewFeature)
        }
    }

    /// The post list beside the reading pane.
    private var readingLayout: some View {
        HStack(spacing: 0) {
            ActivityListView(
                items: visibleActivity,
                directory: directory,
                showsAccounts: feature.accounts.count > 1 && screenState.accountID == nil,
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
                        editLimits: { model.editAccount(named: $0, focusingEntryTolerance: true) },
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
                        },
                        accountID: screenState.accountID
                    )
                } else {
                    ActivityPlaceholderView(isRefreshing: feature.isRefreshing)
                }
            }
            .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The title and one line saying what this page is.
    private var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.string("Activity"))
                .font(DesignTokens.pageTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.string("Every post from your gurus, how it was read, and what each account did."))
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .lineLimit(1)
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            ActivityAccountScope(accounts: feature.accounts, accountID: $screenState.accountID)
            ActivityFilterBar(
                filter: filterBinding, activity: scopedActivity, shown: visibleActivity.count,
                hasMore: feature.nextActivityCursor != nil
            )
            .fixedSize(horizontal: true, vertical: false)
        }
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
                    chosen,
                    visibleIDs: scopedActivity.filter { chosen.includes($0, skipped: model.skippedCalls) }.map(\.id))
            }
        )
    }
}
