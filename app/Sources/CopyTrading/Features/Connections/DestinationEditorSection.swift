import DesktopCore
import SwiftUI

struct DestinationEditorSection: View {
    @Binding var connection: TradingConnectionDraft
    let accountIDs: [String]
    /// The chosen account's limits: its per-stock maximum is the guru's full position, and its
    /// per-order limit trims a bigger buy.
    let policy: TradingAccountPolicy?
    let canRemove: Bool
    let remove: () -> Void

    private var accountChoices: [String] {
        accountIDs.contains(connection.accountID) || connection.accountID.isEmpty
            ? accountIDs
            : accountIDs + [connection.accountID]
    }

    var body: some View {
        Section {
            Picker(L10n.string("Account"), selection: $connection.accountID) {
                ForEach(accountChoices, id: \.self) { accountID in
                    Text(accountID).tag(accountID)
                }
            }
            Toggle(L10n.string("When a call names no size, buy a default share"), isOn: $connection.useDefaultFraction)
                .compactSwitch()
            if connection.useDefaultFraction {
                TextField(L10n.string("Default share"), text: defaultShare, prompt: Text(L10n.string("e.g. %@", "1/6")))
                    .accessibilityLabel(L10n.string("Default share"))
            }
            Text((try? AttributedString(markdown: summary)) ?? AttributedString(summary))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("guru.sizingSummary")
        } header: {
            HStack {
                Text(L10n.string("Copies into"))
                Spacer()
                Button(L10n.string("Remove"), role: .destructive, action: remove)
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .disabled(!canRemove)
            }
        }
    }

    /// The default share as the guru would write it, "1/6", kept as the decimal the engine uses.
    private var defaultShare: Binding<String> {
        Binding(
            get: {
                let stored = connection.defaultFraction.trimmed
                return Decimal(string: stored) == nil ? stored : Humanize.fraction(stored)
            },
            set: { connection.defaultFraction = ExampleEditorSection.decimal(fromSize: $0) }
        )
    }

    private var summary: String {
        SizingSummary.text(connection, policy: policy)
    }
}
