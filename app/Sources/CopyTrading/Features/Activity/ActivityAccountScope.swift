import DesktopCore
import SwiftUI

/// Which account Activity is about. Several accounts: a menu of all of them or one. A single
/// account: its name and Paper/Live badge, so it is always clear whose results these are.
struct ActivityAccountScope: View {
    let accounts: [AccountOverview]
    @Binding var accountID: String?

    var body: some View {
        if accounts.count > 1 {
            Menu {
                Picker(L10n.string("Account"), selection: $accountID) {
                    Text(L10n.string("All accounts")).tag(String?.none)
                    ForEach(accounts, id: \.accountID) { account in
                        Text(account.accountID).tag(String?.some(account.accountID))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(accountID ?? L10n.string("All accounts"), systemImage: "building.columns")
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
            .accessibilityIdentifier("activity.account")
            .help(L10n.string("Show posts for one account, or all of them"))
        } else if let account = accounts.first {
            HStack(spacing: 6) {
                Image(systemName: "building.columns")
                    .foregroundStyle(Palette.tertiaryInk)
                Text(account.accountID)
                    .foregroundStyle(Palette.secondaryInk)
                EnvironmentBadge(environment: account.environment)
            }
            .font(DesignTokens.caption)
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.string("Account %@", account.accountID))
        }
    }
}
