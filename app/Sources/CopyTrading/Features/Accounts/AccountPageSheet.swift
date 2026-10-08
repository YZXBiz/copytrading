import DesktopCore
import SwiftUI

/// The sheet an account page raises: copying or reviewing a post, or evaluating an old one.
struct AccountPageSheet: View {
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
                confirmOrders: confirmOrders,
                engineStopped: model.runtimeState == .stopped || model.runtimeState == .failed,
                startEngine: model.requestStart
            )
        case .historicalEvaluation(let source):
            HistoricalProfileEvaluationSheet(source: source, model: model)
        }
    }

    private func confirmOrders(_ accountIDs: Set<String>) async throws {
        try await model.confirmOrders(for: accountIDs, reason: L10n.string("send these orders"))
    }
}
