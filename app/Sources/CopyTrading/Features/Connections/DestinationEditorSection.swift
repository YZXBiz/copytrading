import DesktopCore
import SwiftUI

/// The one account a guru copies into (ADR-0007), and what the guru's calls come to in that
/// account (ADR-0010).
struct DestinationEditorSection: View {
    @Binding var connection: TradingConnectionDraft?
    /// Accounts no other guru copies into; each account copies one guru.
    let accountIDs: [String]
    /// The chosen account's limits: its per-stock maximum is the full position until the guru has
    /// its own, and its largest single buy cuts a bigger buy (ADR-0010).
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
                if connection != nil {
                    SheetRow(
                        title: L10n.string("Full position"),
                        hint: L10n.string("The guru's whole position, in dollars. A 1/6 call buys a sixth."),
                        labelsControl: true
                    ) {
                        TextField(
                            L10n.string("Full position"), text: fullPosition,
                            prompt: Text(policy?.maxSymbolUSD.trimmed.nilIfEmpty ?? L10n.string("Required"))
                                .foregroundStyle(Palette.tertiaryInk)
                        )
                        .accessibilityLabel(L10n.string("Full position"))
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .sheetInput(width: DesignTokens.sheetNumberWidth)
                        .accessibilityIdentifier("guru.fullPosition")
                    }
                }
                if let sizing {
                    ForEach(sizing.figures) { figure in
                        sizingRow(figure)
                    }
                }
            }
            .accessibilityIdentifier("guru.sizingSummary")
        } footer: {
            if let sizing {
                if let warning = sizing.warning {
                    Text(warning)
                } else if let note = sizing.note {
                    Text(note)
                }
            } else if connection != nil {
                Text(L10n.string("Set the guru's full position, or this account's max per stock."))
            }
        }
    }

    /// The guru's own full position; empty follows the account's maximum per stock.
    private var fullPosition: Binding<String> {
        Binding(
            get: { connection?.fullPositionUSD ?? "" },
            set: { connection?.fullPositionUSD = $0 }
        )
    }

    private var sizing: SizingSummary? {
        connection.flatMap { SizingSummary.of($0, policy: policy) }
    }

    /// What one kind of call buys, as a reading: the amount at the trailing edge, with what it
    /// asked for beside it when the largest single buy cut it down.
    private func sizingRow(_ figure: SizingSummary.Figure) -> some View {
        SheetRow(title: figure.label, isReading: true) {
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
