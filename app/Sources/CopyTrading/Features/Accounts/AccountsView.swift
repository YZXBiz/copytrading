import DesktopCore
import SwiftUI

/// Each broker account as one working page, plus any account added in the setup but not saved
/// yet. Accounts are added and edited here; changes wait until the setup is checked and started.
struct AccountsView: View {
    @Bindable var model: AppModel
    let feature: AccountFeatureModel
    @State private var hoveredDraftID: UUID?

    private let contentMaxWidth: CGFloat = 1_040

    /// Accounts in the setup that are not saved yet. A saved account the engine has not read yet
    /// is not one of them; it appears once the engine reads it.
    private var draftOnlyAccounts: [TradingAccountDraft] {
        let known = Set(feature.accounts.map(\.accountID))
            .union(model.savedTradingConfiguration?.accounts.map(\.id) ?? [])
        return model.setupDraft.accounts.filter { !known.contains($0.name.trimmed) }
    }

    private var isEmpty: Bool {
        feature.accounts.isEmpty && draftOnlyAccounts.isEmpty && !feature.isRefreshing && feature.errors["read"] == nil
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
                                RoundGlassButton(title: "Add Account", symbol: "plus.circle.fill", action: model.addAccount)
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
            ForEach(draftOnlyAccounts) { account in
                Button {
                    model.setupEditor = .account(account.id)
                } label: {
                    DraftAccountCard(
                        account: account,
                        hasSavedKeys: model.savedKeyAccountIDs.contains(account.name.trimmed),
                        isHovered: hoveredDraftID == account.id
                    )
                }
                .buttonStyle(QuietPressButtonStyle())
                .onHover { hoveredDraftID = $0 ? account.id : (hoveredDraftID == account.id ? nil : hoveredDraftID) }
                .accessibilityHint(L10n.string("Edits this account"))
                .accessibilityIdentifier("accounts.draft.\(account.name.trimmed)")
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

    private func loadMore() {
        Task { await feature.loadMoreAccounts(using: model.accountActions()) }
    }
}
