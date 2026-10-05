import DesktopCore
import SwiftUI

/// The one account a guru copies into (ADR-0007), the share a call with no size buys, and what
/// the guru's calls come to in that account.
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
                Toggle(L10n.string("When a call names no size, buy a default share"), isOn: useDefaultShare)
                    .compactSwitch()
                if draft.useDefaultFraction {
                    TextField(L10n.string("Default share"), text: defaultShare, prompt: Text(L10n.string("e.g. %@", "1/6")))
                        .accessibilityLabel(L10n.string("Default share"))
                }
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
            Text(L10n.string("Each account copies one guru, so its maximum per stock is that guru's full position."))
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

    private var useDefaultShare: Binding<Bool> {
        Binding(
            get: { connection?.useDefaultFraction ?? true },
            set: { connection?.useDefaultFraction = $0 }
        )
    }

    /// The default share as the guru would write it, "1/6", kept as the decimal the engine uses.
    private var defaultShare: Binding<String> {
        Binding(
            get: {
                let stored = connection?.defaultFraction.trimmed ?? ""
                return Decimal(string: stored) == nil ? stored : Humanize.fraction(stored)
            },
            set: { connection?.defaultFraction = ExampleEditorSection.decimal(fromSize: $0) }
        )
    }
}
