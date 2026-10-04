import SwiftUI

/// Accounts before any is added or read: where orders go, and the way to add the first one.
struct AccountsInvitation: View {
    let model: AppModel

    private var isSetUp: Bool { model.savedTradingConfiguration != nil }

    var body: some View {
        InvitationCard(
            lead: "Your accounts,",
            emphasis: "inside your limits",
            message: isSetUp
                ? "Accounts appear once the engine has read them."
                : "Add the broker account orders go to. Start with an Alpaca paper account: it trades pretend money at real prices."
        ) {
            AccountsInvitationFigure()
        } actions: {
            if !isSetUp {
                Button(L10n.string("Add Account"), systemImage: "plus", action: model.addAccount)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .accessibilityIdentifier("accounts.addAccount")
            }
        }
    }
}
