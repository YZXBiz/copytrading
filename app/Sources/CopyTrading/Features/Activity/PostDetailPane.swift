import DesktopCore
import SwiftUI

/// The post chosen on an account or guru page, beside it: the Activity card, with its review, copy and
/// evaluation sheets.
struct PostDetailPane: View {
    let item: SourceActivity
    let model: AppModel
    let feature: AccountFeatureModel
    let close: () -> Void
    @State private var reviewFeature = ManualReviewFeatureModel()
    @State private var selectedSheet: ActivitySheet?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(L10n.string("Close"), systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(QuietPressButtonStyle())
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
                    .keyboardShortcut(.cancelAction)
                    .help(L10n.string("Close"))
                    .accessibilityIdentifier("post.close")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            ActivityDetailView(
                item: item,
                guruName: GuruDirectory(model.savedTradingConfiguration).name(for: item.guruID),
                canReview: !feature.accounts.isEmpty,
                canEvaluate: model.savedTradingConfiguration?.routes.isEmpty == false,
                skippedCalls: model.skippedCalls,
                review: review,
                copy: copy,
                evaluate: evaluate,
                editLimits: editLimits,
                reviewHoldings: reviewHoldings,
                resume: ResumeWait(
                    item, waiting: ResumeWait.waitingAccounts(feature.accounts),
                    signalAge: ResumeWait.signalAge(in: model.savedTradingConfiguration)),
                startCopying: startCopying,
                stories: stories,
                directory: GuruDirectory(model.savedTradingConfiguration),
                postText: postText
            )
            .task(id: item.sourceID) { await loadFeeds() }
        }
        .sheet(item: $selectedSheet, onDismiss: reviewFeature.clearPrivateEvidence) { selected in
            ActivitySheetContent(selected: selected, model: model, feature: feature, reviewFeature: reviewFeature)
        }
    }

    /// Each account's story of the holding this post's buy opened or joined, from its activity.
    private var stories: [String: PositionStory] {
        var stories: [String: PositionStory] = [:]
        for destination in item.destinations {
            if let story = PositionStory(post: item.sourceID, feed: feature.feeds[destination.accountID] ?? []) {
                stories[destination.accountID] = story
            }
        }
        return stories
    }

    /// The words of another post, while Activity still holds it.
    private func postText(_ sourceID: String) -> String? {
        feature.activity.first { $0.sourceID == sourceID }?.text
    }

    /// A post opened from a guru page may come before its accounts' activity has been read.
    private func loadFeeds() async {
        for destination in item.destinations where feature.feeds[destination.accountID] == nil {
            await feature.loadFeed(accountID: destination.accountID, using: model.accountActions())
        }
    }

    private func review() {
        selectedSheet = .manualReview(item, copying: nil)
    }

    private func copy(_ call: WaitingCall) {
        selectedSheet = .manualReview(item, copying: call)
    }

    private func evaluate() {
        selectedSheet = .historicalEvaluation(item)
    }

    private func editLimits(_ accountID: String) {
        model.editAccount(named: accountID, focus: .entryTolerance)
    }

    private func reviewHoldings(_ accountID: String) {
        model.selectedScreen = .account(accountID)
    }

    private func startCopying(_ accountID: String) {
        let environment = feature.accounts.first { $0.accountID == accountID }?.environment
        Task { await model.startCopying(into: accountID, environment: environment, feature: feature) }
    }
}
