import DesktopCore
import SwiftUI

/// One broker account as the page the owner works from: its money and curve, how close it runs
/// to its limits, the calls waiting on the owner, what it holds, and what happened in it.
struct AccountPage: View {
    let accountID: String
    let model: AppModel
    let feature: AccountFeatureModel
    let activityState: ActivityScreenState
    /// A detail pane shares the window, so the chart shortens and the page drops its width cap.
    var isSharingWidth = false
    @State private var reviewFeature = ManualReviewFeatureModel()
    @State private var sheet: ActivitySheet?

    private static let contentMaxWidth: CGFloat = 1_040

    var body: some View {
        let account = feature.accounts.first { $0.accountID == accountID }
        let configuration = model.savedTradingConfiguration?.accounts.first { $0.id == accountID }
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if let account {
                    AccountPageContent(
                        account: account, policy: configuration?.policy, model: model, feature: feature,
                        activityState: activityState, isSharingWidth: isSharingWidth, sheet: $sheet)
                } else {
                    AccountPageWaiting(accountID: accountID, configuration: configuration, model: model, feature: feature)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: isSharingWidth ? .infinity : Self.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        .navigationTitle(accountID)
        .sheet(item: $sheet, onDismiss: reviewFeature.clearPrivateEvidence) { selected in
            ActivitySheetContent(selected: selected, model: model, feature: feature, reviewFeature: reviewFeature)
        }
    }
}
