import DesktopCore
import SwiftUI

/// One broker account as the page the owner works from: its money and curve, how close it runs
/// to its limits, the calls waiting on the owner, what it holds, and what happened in it. Choosing
/// a post opens it beside the page, and the page tightens to share the window.
struct AccountPage: View {
    let accountID: String
    let model: AppModel
    let feature: AccountFeatureModel
    let activityState: ActivityScreenState
    @State private var reviewFeature = ManualReviewFeatureModel()
    @State private var sheet: ActivitySheet?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let contentMaxWidth: CGFloat = 1_040

    private var selectedPost: SourceActivity? {
        guard let id = activityState.selectedActivityID else { return nil }
        return feature.activity.first { $0.id == id }
    }

    var body: some View {
        let isSharingWidth = selectedPost != nil
        HStack(spacing: 0) {
            page(isSharingWidth: isSharingWidth)
                .frame(minWidth: 460)
            if let selectedPost {
                // The post sits on the canvas grey beside the white page: tone parts them, not a rule.
                PostDetailPane(item: selectedPost, model: model, feature: feature, close: closePost)
                    .frame(width: 460)
                    .background(Palette.canvas)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Palette.page)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.28), value: isSharingWidth)
        .navigationTitle(accountID)
        .sheet(item: $sheet, onDismiss: reviewFeature.clearPrivateEvidence) { selected in
            ActivitySheetContent(selected: selected, model: model, feature: feature, reviewFeature: reviewFeature)
        }
    }

    private func page(isSharingWidth: Bool) -> some View {
        let account = feature.accounts.first { $0.accountID == accountID }
        let configuration = model.savedTradingConfiguration?.accounts.first { $0.id == accountID }
        return ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if let account {
                    AccountPageContent(
                        account: account, policy: configuration?.policy, model: model, feature: feature,
                        isSharingWidth: isSharingWidth, selectedPostID: activityState.selectedActivityID,
                        sheet: $sheet, openPost: openPost)
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
    }

    /// The same post again closes it, like choosing a selected row in Mail.
    private func openPost(_ id: SourceActivity.ID) {
        activityState.selectedActivityID = activityState.selectedActivityID == id ? nil : id
    }

    private func closePost() {
        activityState.selectedActivityID = nil
    }
}
