import SwiftUI

/// People before anyone is added: who a guru is to CopyTrading, and the one way to add one.
struct PeopleInvitation: View {
    let addGuru: () -> Void

    var body: some View {
        InvitationCard(
            lead: "Who will you",
            emphasis: "copy?",
            message:
                "Add the trader you want to follow: the channel they post in, how to read their calls, and how much each account puts into one."
        ) {
            PeopleInvitationFigure()
        } actions: {
            Button(L10n.string("Add Guru"), systemImage: "plus", action: addGuru)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .accessibilityIdentifier("people.addGuru")
        }
    }
}
