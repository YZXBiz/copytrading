import SwiftUI

/// Accounts before any is read: where orders go, and the way to Connections, where they are set up.
struct AccountsInvitation: View {
    let model: AppModel

    private var isSetUp: Bool { model.savedTradingConfiguration != nil }

    var body: some View {
        InvitationCard(
            lead: "Your accounts,",
            emphasis: "inside your limits",
            message: isSetUp
                ? "Accounts appear once the engine has read them."
                : "Your broker accounts show here once you set them up in Connections. Start with an Alpaca paper account: it trades pretend money at real prices."
        ) {
            AccountsInvitationFigure()
        } actions: {
            if !isSetUp {
                Button(L10n.string("Set Up in Connections"), systemImage: "slider.horizontal.3") {
                    model.selectedScreen = .connections
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .accessibilityIdentifier("accounts.openConnections")
            }
        }
    }
}
