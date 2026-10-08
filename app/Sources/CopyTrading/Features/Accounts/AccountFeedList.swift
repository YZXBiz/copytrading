import DesktopCore
import SwiftUI

/// The account's recent activity in plain sentences: what was bought and sold, by a guru's post
/// or by the owner, and the owner's own changes. The raw event log stays in Diagnostics.
struct AccountFeedList: View {
    let accountID: String
    let model: AppModel
    let feature: AccountFeatureModel

    private var items: [AccountFeedItem] { feature.feeds[accountID] ?? [] }

    var body: some View {
        PageSection("Recent activity", symbol: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 0) {
                if let error = feature.errors["feed:\(accountID)"] {
                    Callout(error, tone: .critical)
                        .accessibilityLabel(L10n.string("Account activity error: %@", error))
                }
                if items.isEmpty {
                    Text(L10n.string("Nothing has been bought or sold in this account yet."))
                        .foregroundStyle(Palette.secondaryInk)
                        .font(.callout)
                }
                ForEach(items) { item in
                    AccountFeedRow(item: item, directory: GuruDirectory(model.savedTradingConfiguration))
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if item.id != items.last?.id {
                                Rectangle().fill(Palette.hairline).frame(height: 1)
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

    private func loadMore() {
        Task { await feature.loadFeed(accountID: accountID, more: true, using: model.accountActions()) }
    }
}
