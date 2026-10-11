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
                resumeEntries: resumeEntries
            )
        }
        .sheet(item: $selectedSheet, onDismiss: reviewFeature.clearPrivateEvidence) { selected in
            ActivitySheetContent(selected: selected, model: model, feature: feature, reviewFeature: reviewFeature)
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

    private func resumeEntries(_ accountID: String) {
        let environment = feature.accounts.first { $0.accountID == accountID }?.environment
        Task { await model.resumeEntries(accountID: accountID, environment: environment, feature: feature) }
    }
}
