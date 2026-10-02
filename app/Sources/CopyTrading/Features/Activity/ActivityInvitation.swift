import SwiftUI

/// Activity before any post has arrived: what will appear here, and what to do until then.
struct ActivityInvitation: View {
    let model: AppModel

    var body: some View {
        InvitationCard(
            lead: "Every post",
            emphasis: "lands here",
            message:
                "Every post from the channels you follow appears here, with what CopyTrading understood and what each account did about it."
        ) {
            ActivityInvitationFigure()
        } actions: {
            if model.savedTradingConfiguration == nil {
                Button(L10n.string("Continue Getting Started"), action: openGuide)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .accessibilityIdentifier("activity.gettingStarted")
            } else {
                Text(
                    L10n.string(
                        "Nothing has been posted in your gurus’ channels since copying started. New posts show up here within seconds.")
                )
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func openGuide() {
        model.guideAnchor = .setUp
        model.selectedScreen = .gettingStarted
    }
}
