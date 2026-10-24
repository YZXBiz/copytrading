import DesktopCore
import SwiftUI

/// Records of accounts the setup no longer has, so they never wait unseen for a name to be used
/// again. Each can be deleted; nothing is deleted on its own.
struct EarlierAccountsSection: View {
    let model: AppModel

    var body: some View {
        if let feature = model.accountFeature {
            let earlier = Self.earlier(feature.accounts, saved: model.savedTradingConfiguration)
            if !earlier.isEmpty {
                SettingsSection(
                    title: "Earlier Accounts",
                    hint: "Records of accounts no longer in your setup. The same keys under any name pick theirs up again."
                ) {
                    ForEach(earlier) { account in
                        EarlierAccountRow(
                            account: account, problem: feature.errors[account.accountID],
                            isWorking: feature.pendingAccounts.contains(account.accountID)
                        ) {
                            Task { await feature.deleteRecord(account.accountID, using: model.accountActions()) }
                        }
                    }
                }
            }
        }
    }

    /// Every record whose name the saved setup doesn't use.
    static func earlier(_ accounts: [AccountOverview], saved: TradingConfiguration?) -> [AccountOverview] {
        let inSetup = Set(saved?.accounts.map(\.id) ?? [])
        return accounts.filter { !inSetup.contains($0.accountID) }
    }
}
