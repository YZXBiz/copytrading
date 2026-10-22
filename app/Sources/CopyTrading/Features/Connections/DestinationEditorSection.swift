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
    /// Who the sizing sentence is about: "Zhao's full position is $1,000."
    var guruName = ""

    var body: some View {
        SheetSection(L10n.string("Copies into")) {
            if accountIDs.isEmpty && connection == nil {
                Text(L10n.string("Every account already copies a guru. Add a broker account in Connections first."))
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(.vertical, 12)
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
            if let draft = connection {
                if let sizing = SizingSummary.of(draft, policy: policy) {
                    sizingLines(sizing)
                } else {
                    Text(L10n.string("First set this account's max per stock. It's the guru's full position."))
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.top, 12)
                }
            }
        }
    }

    /// What each kind of call buys, in plain lines: the guru's full position first, then each call
    /// and what it buys, saying so when the per-order limit cut it down.
    private func sizingLines(_ sizing: SizingSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let full = sizing.figures.first {
                Text(
                    guruName.trimmed.isEmpty
                        ? L10n.string("The guru's full position is %@, this account's max per stock.", full.amount)
                        : L10n.string("%@'s full position is %@, this account's max per stock.", guruName.trimmed, full.amount)
                )
                .foregroundStyle(Palette.ink)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sizing.figures.dropFirst()) { figure in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(figure.label)
                            .foregroundStyle(Palette.secondaryInk)
                        Spacer(minLength: 12)
                        if let asked = figure.cutFrom {
                            Text(L10n.string("cut from %@", asked))
                                .font(DesignTokens.caption)
                                .foregroundStyle(Palette.tertiaryInk)
                        }
                        Text(figure.amount)
                            .font(DesignTokens.rowTitle)
                            .foregroundStyle(Palette.ink)
                    }
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    if figure.id != sizing.figures.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(Palette.group, in: .rect(cornerRadius: 10))
            if let note = sizing.note {
                Text(note)
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
        .padding(.top, 6)
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
