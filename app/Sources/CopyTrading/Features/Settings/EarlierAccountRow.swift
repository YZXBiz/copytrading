import DesktopCore
import SwiftUI

/// The record of an account no longer in the setup: its name, the Alpaca account it belongs to,
/// what CopyTrading still holds there, and when it last changed. Delete asks first.
struct EarlierAccountRow: View {
    let account: AccountOverview
    var problem: String?
    var isWorking = false
    let delete: () -> Void
    @State private var confirmsDelete = false

    var body: some View {
        SettingsRow(title: account.accountID, detail: detail, tone: problem == nil ? nil : .caution) {
            Button(L10n.string("Delete…"), role: .destructive) { confirmsDelete = true }
                .buttonStyle(PageButtonStyle())
                .disabled(isWorking)
                .accessibilityLabel(L10n.string("Delete the record of %@", account.accountID))
                .accessibilityIdentifier("settings.earlierAccount.delete.\(account.accountID)")
                .confirmationDialog(
                    L10n.string("Delete the record of %@?", account.accountID), isPresented: $confirmsDelete
                ) {
                    Button(L10n.string("Delete Record"), role: .destructive, action: delete)
                    Button(L10n.string("Keep"), role: .cancel) {}
                } message: {
                    Text(
                        L10n.string(
                            "CopyTrading forgets which shares it bought there, so no guru's sell reaches them. The shares stay at Alpaca."
                        ))
                }
        }
    }

    /// "Alpaca paper account ending 0f11 · 2 copied buys · Last active Oct 12, 2:15 PM".
    private var detail: String {
        let alpaca = L10n.string(
            account.environment == .live ? "Alpaca live account ending %@" : "Alpaca paper account ending %@",
            String(account.brokerIdentity.suffix(4)))
        let buys = account.positions.reduce(0) { $0 + $1.lots.count }
        var parts = [alpaca, buys == 0 ? L10n.string("No copied shares") : Humanize.count(buys, "copied buy")]
        if let at = account.lastActivityAt {
            parts.append(L10n.string("Last active %@", Humanize.timestamp(at)))
        }
        let summary = parts.joined(separator: " · ")
        return problem.map { "\(summary)\n\($0)" } ?? summary
    }
}
