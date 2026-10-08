import DesktopCore
import SwiftUI

/// The account's recent activity in plain sentences: what was bought and sold, by a guru's post
/// or by the owner, and the owner's own changes. The raw event log stays in Diagnostics.
struct AccountFeedList: View {
    let accountID: String
    let model: AppModel
    let feature: AccountFeatureModel
    let selectedPostID: SourceActivity.ID?
    let openPost: (SourceActivity.ID) -> Void

    private var items: [AccountFeedItem] { feature.feeds[accountID] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ListHeading("Activity")
            VStack(alignment: .leading, spacing: 0) {
                if let error = feature.errors["feed:\(accountID)"] {
                    Callout(error, tone: .critical)
                        .accessibilityLabel(L10n.string("Account activity error: %@", error))
                }
                if items.isEmpty {
                    InkEmptyState(message: L10n.string("Nothing has been bought or sold in this account yet."))
                        .padding(.vertical, 8)
                }
                let directory = GuruDirectory(model.savedTradingConfiguration)
                ForEach(items) { item in
                    let post = post(for: item)
                    AccountFeedRow(
                        item: item, directory: directory, isSelected: post != nil && post?.id == selectedPostID,
                        open: post.map { post in { openPost(post.id) } }
                    )
                    .overlay(alignment: .bottom) {
                        if item.id != items.last?.id {
                            Hairline()
                        }
                    }
                }
                if feature.feedCursors[accountID] != nil {
                    Button(L10n.string("Show Older Activity"), action: loadMore)
                        .buttonStyle(.link)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: accountID) {
            if feature.feeds[accountID] == nil {
                await feature.loadFeed(accountID: accountID, using: model.accountActions())
            }
        }
    }

    /// The guru post an order row came from, while Activity still holds it.
    private func post(for item: AccountFeedItem) -> SourceActivity? {
        guard let messageID = item.messageID else { return nil }
        return feature.activity.first { $0.sourceID == messageID }
    }

    private func loadMore() {
        Task { await feature.loadFeed(accountID: accountID, more: true, using: model.accountActions()) }
    }
}
