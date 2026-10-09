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
            if accountIDs.isEmpty && connection == nil {
                Text(L10n.string("Every account already copies a guru. Add a broker account in Connections first."))
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(.vertical, 12)
            } else {
                SheetRow(title: L10n.string("Account")) {
                    SheetMenu(
                        label: L10n.string("Account"),
                        choices: (connection == nil ? [("", L10n.string("Choose an account"))] : [])
                            + accountChoices.map { ($0, $0) },
                        selection: account)
                }
            }
            if let draft = connection {
                if let sizing = SizingSummary.of(draft, policy: policy) {
                    sizingFigures(sizing)
                } else {
                    Text(L10n.string("First set this account's max per stock. It's the guru's full position."))
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.top, 12)
                }
            }
        } footer: {
            Text(L10n.string("Each account follows one guru. Its max per stock is that guru's full position."))
        }
    }

    /// What each kind of call buys, as figures in a row: a tracked label over a clear amount. A
    /// figure the per-order limit cut down carries a small marker and the note says why.
    private func sizingFigures(_ sizing: SizingSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 28) {
                ForEach(sizing.figures) { figure in
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(figure.label)
                        Text(figure.amount)
                            .font(DisplayFont.font(size: 22, weight: .medium, relativeTo: .title3))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                            .markerHighlight(figure.isTrimmed)
                    }
                    .fixedSize()
                }
                Spacer(minLength: 0)
            }
            if let note = sizing.note {
                Text(note)
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guru.sizingSummary")
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
