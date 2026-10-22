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
        SheetSection(L10n.string("Copies into")) {
            SheetGroup {
                if accountIDs.isEmpty && connection == nil {
                    SheetRow(
                        title: L10n.string("Account"),
                        hint: L10n.string("Every account already copies a guru. Add a broker account in Connections first.")
                    ) { EmptyView() }
                } else {
                    SheetRow(
                        title: L10n.string("Account"), hint: L10n.string("Each account copies one guru."), labelsControl: true
                    ) {
                        SheetMenu(
                            label: L10n.string("Account"),
                            choices: (connection == nil ? [("", L10n.string("Choose an account"))] : [])
                                + accountChoices.map { ($0, $0) },
                            selection: account)
                    }
                }
                if let sizing {
                    ForEach(sizing.figures) { figure in
                        sizingRow(figure, isFull: figure.id == sizing.figures.first?.id)
                    }
                }
            }
            .accessibilityIdentifier("guru.sizingSummary")
        } footer: {
            if let sizing {
                if let note = sizing.note {
                    Text(note)
                }
            } else if connection != nil {
                Text(L10n.string("First set this account's max per stock. It's the guru's full position."))
            }
        }
    }

    private var sizing: SizingSummary? {
        connection.flatMap { SizingSummary.of($0, policy: policy) }
    }

    /// What one kind of call buys, as a reading: the amount at the trailing edge, with what it
    /// asked for beside it when the per-order limit cut it down.
    private func sizingRow(_ figure: SizingSummary.Figure, isFull: Bool) -> some View {
        SheetRow(
            title: figure.label,
            hint: isFull ? L10n.string("This account's max per stock.") : nil,
            isReading: true
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let asked = figure.cutFrom {
                    Text(L10n.string("cut from %@", asked))
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                Text(figure.amount)
                    .font(DesignTokens.rowTitle)
                    .foregroundStyle(Palette.ink)
                    .markerHighlight(figure.isTrimmed)
            }
            .monospacedDigit()
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
