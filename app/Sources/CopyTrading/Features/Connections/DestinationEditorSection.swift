import DesktopCore
import SwiftUI

/// The one account a guru copies into (ADR-0007), and what the guru's calls come to in that
/// account (ADR-0010).
struct DestinationEditorSection: View {
    @Binding var connection: TradingConnectionDraft?
    /// Accounts no other guru copies into; each account copies one guru.
    let accountIDs: [String]
    /// The chosen account's limits: its per-stock maximum is the guru's full position, and its
    /// per-order limit trims a bigger buy.
    let policy: TradingAccountPolicy?

    var body: some View {
        Section {
            if accountIDs.isEmpty && connection == nil {
                Text(L10n.string("Every account already copies a guru. Add a broker account in Connections first."))
                    .foregroundStyle(.secondary)
            } else {
                Picker(L10n.string("Account"), selection: account) {
                    if connection == nil {
                        Text(L10n.string("Choose an account")).tag("")
                    }
                    ForEach(accountChoices, id: \.self) { accountID in
                        Text(accountID).tag(accountID)
                    }
                }
            }
            if let draft = connection {
                let summary = SizingSummary.text(draft, policy: policy)
                Text((try? AttributedString(markdown: summary)) ?? AttributedString(summary))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("guru.sizingSummary")
            }
        } header: {
            Text(L10n.string("Copies into"))
        } footer: {
            Text(L10n.string("Each account follows one guru. Its max per stock is that guru's full position."))
        }
    }

    private var accountChoices: [String] {
        guard let chosen = connection?.accountID, !chosen.isEmpty, !accountIDs.contains(chosen) else {
            return accountIDs
        }
        return accountIDs + [chosen]
    }

    private var account: Binding<String> {
        Binding(
            get: { connection?.accountID ?? "" },
            set: { accountID in
                guard !accountID.isEmpty else { return }
                if connection == nil {
                    connection = TradingConnectionDraft(accountID: accountID)
                } else {
                    connection?.accountID = accountID
                }
            }
        )
    }
}
