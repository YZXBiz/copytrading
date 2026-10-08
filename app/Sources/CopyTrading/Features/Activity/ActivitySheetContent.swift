import DesktopCore
import SwiftUI

/// The sheet a post's card asks for: review or copy its calls, or evaluate an earlier post.
struct ActivitySheetContent: View {
    let selected: ActivitySheet
    let model: AppModel
    let feature: AccountFeatureModel
    let reviewFeature: ManualReviewFeatureModel

    var body: some View {
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
}
