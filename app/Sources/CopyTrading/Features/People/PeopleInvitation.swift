import SwiftUI

/// People before any guru is saved: who a guru is to CopyTrading, and the way to Connections,
/// where they are added.
struct PeopleInvitation: View {
    /// Gurus are added in Connections but not saved yet: they show here once copying starts.
    var hasUnsavedGurus = false
    let openConnections: () -> Void

    var body: some View {
        InvitationCard(
            lead: "The traders",
            emphasis: "you choose to copy",
            message: hasUnsavedGurus
                ? "Your gurus show here once you start copying. Start Copying in Connections checks and saves them."
                : "The traders you follow show here once you add them in Connections: the channel they post in, how to read their calls, and the account that copies them."
        ) {
            PeopleInvitationFigure()
        } actions: {
            Button(
                L10n.string(hasUnsavedGurus ? "Open Connections" : "Set Up in Connections"), systemImage: "slider.horizontal.3",
                action: openConnections
            )
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .accessibilityIdentifier("people.openConnections")
        }
    }
}
