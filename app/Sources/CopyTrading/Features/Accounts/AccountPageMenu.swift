import DesktopCore
import SwiftUI

/// The account's less frequent controls behind ⋯: its keys, limits, and what it does after a
/// restart, all on its sheet in Connections.
struct AccountPageMenu: View {
    let account: AccountOverview
    let isInSetup: Bool
    let model: AppModel

    var body: some View {
        Menu(L10n.string("More for this account"), systemImage: "ellipsis") {
            Button(L10n.string("Edit in Connections"), systemImage: "point.3.connected.trianglepath.dotted", action: editInConnections)
                .disabled(!isInSetup)
        }
        .labelStyle(.iconOnly)
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(PageButtonStyle(horizontalPadding: 8))
        .fixedSize()
        .help(L10n.string("More for this account"))
        .accessibilityIdentifier("account.more")
    }

    private func editInConnections() {
        model.selectedScreen = .connections
        model.editAccount(named: account.accountID)
    }
}
