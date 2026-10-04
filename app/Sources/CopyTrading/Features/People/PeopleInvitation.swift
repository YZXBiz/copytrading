import SwiftUI

/// People before any guru is saved: who a guru is to CopyTrading, and the way to Connections,
/// where they are added.
struct PeopleInvitation: View {
    let openConnections: () -> Void

    var body: some View {
        InvitationCard(
            lead: "The traders",
            emphasis: "you choose to copy",
            message:
                "The traders you follow show here once you add them in Connections: the channel they post in, how to read their calls, and how much each account puts into one."
        ) {
            PeopleInvitationFigure()
        } actions: {
            Button(L10n.string("Set Up in Connections"), systemImage: "slider.horizontal.3", action: openConnections)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .accessibilityIdentifier("people.openConnections")
        }
    }
}
