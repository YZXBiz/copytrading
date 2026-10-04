import DesktopCore
import SwiftUI

/// Each broker account as one working page, once Connections has set it up and the engine has
/// read it. Accounts are added and edited in Connections.
struct AccountsView: View {
    @Bindable var model: AppModel
    let feature: AccountFeatureModel

    private let contentMaxWidth: CGFloat = 1_040

    private var isEmpty: Bool {
        feature.accounts.isEmpty && !feature.isRefreshing && feature.errors["read"] == nil
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = min(
                max(0, geometry.size.width - DesignTokens.pagePadding * 2), contentMaxWidth
            )
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        PageHeader(
                            L10n.string("Accounts"),
                            actions: {
                                RoundGlassButton(
                                    title: "Edit in Connections", symbol: "slider.horizontal.3", action: openConnections)
                            })
                        if isEmpty {
                            AccountsInvitation(model: model)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 28)
                        } else {
                            accountList
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding([.horizontal, .bottom], DesignTokens.pagePadding)
                    .padding(.top, DesignTokens.pageTopPadding)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .onChange(of: model.requestedAccountID, initial: true) { _, id in
                    guard let id else { return }
                    model.requestedAccountID = nil
                    reader.scrollTo(id, anchor: .top)
                }
            }
        }
        .navigationTitle(L10n.string("Accounts"))
    }

    private var accountList: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            if let error = feature.errors["read"] {
                Callout(error, tone: .critical)
                    .accessibilityLabel(L10n.string("Account data error: %@", error))
            }
            ForEach(feature.unavailableAccounts) { gap in
                Callout(
                    L10n.string("Account %@ %@, so its data is not shown.", gap.accountID, gap.explanation),
                    tone: .caution
                )
            }
            ForEach(feature.accounts) { account in
                AccountSection(
                    account: account,
                    policy: model.savedTradingConfiguration?.accounts.first { $0.id == account.accountID }?.policy,
                    model: model,
                    feature: feature
                )
                .id(account.accountID)
            }
            if feature.nextAccountCursor != nil {
                Button(L10n.string("Load More Accounts"), action: loadMore)
                    .disabled(feature.isLoadingMoreAccounts)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func openConnections() {
        model.selectedScreen = .connections
    }

    private func loadMore() {
        Task { await feature.loadMoreAccounts(using: model.accountActions()) }
    }
}
