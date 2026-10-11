import DesktopCore
import SwiftUI

/// The broker accounts step: each account in the setup with how it stands, then a way to add
/// another. Before any is added, a paper and a live Alpaca account to connect.
struct BrokerAccountsRows: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsSection {
            if model.setupDraft.accounts.isEmpty {
                ConnectionServiceRow(
                    brand: "alpaca",
                    title: L10n.string("Alpaca paper account"),
                    detail: L10n.string("Pretend money at real prices. Start here."),
                    action: L10n.string("Connect"),
                    identifier: "connections.accounts.paper"
                ) { model.addAccount(.paper) }
                ConnectionServiceRow(
                    brand: "alpaca",
                    title: L10n.string("Alpaca live account"),
                    detail: L10n.string("Real money. Each order still stays inside your limits."),
                    action: L10n.string("Connect"),
                    identifier: "connections.accounts.live"
                ) { model.addAccount(.live) }
            } else {
                ForEach(model.setupDraft.accounts) { account in
                    let status = ConnectionStatus.account(account, in: model)
                    ConnectionServiceRow(
                        brand: "alpaca",
                        title: L10n.string(
                            "%@ · %@", name(of: account), L10n.string(account.environment == .live ? "Live" : "Paper")),
                        detail: status.text,
                        tone: status.tone,
                        action: L10n.string("Edit"),
                        identifier: "connections.account.\(account.name.trimmed)"
                    ) { model.setupEditor = .account(account.id) }
                }
                ConnectionServiceRow(
                    brand: nil,
                    symbol: "plus",
                    title: L10n.string("Add another account"),
                    identifier: "connections.accounts.add"
                ) { model.addAccount(.paper) }
            }
        }
    }

    private func name(of account: TradingAccountDraft) -> String {
        account.name.trimmed.isEmpty ? L10n.string("Unnamed account") : account.name.trimmed
    }
}
