import SwiftUI

/// Today before anything is saved: an invitation that shows what will appear here, the five setup
/// steps as a route with the finished ones filled, and the way back to the guide.
struct TodaySetupPrompt: View {
    let model: AppModel

    private var progress: SetupProgress { model.setupProgress }

    var body: some View {
        InvitationCard(
            lead: "Your trading day,",
            emphasis: "at a glance",
            message:
                "Once you finish Getting Started, Today shows how your accounts are doing, what your gurus posted, and how close each account is to its limits."
        ) {
            TodayInvitationFigure()
        } actions: {
            VStack(alignment: .leading, spacing: 22) {
                RouteLine(
                    stops: SetupStep.allCases.map { step in
                        RouteStop(
                            title: step.shortTitle,
                            state: progress.isDone(step) ? "Done" : "To do",
                            tone: progress.isDone(step) ? .positive : .inactive)
                    })
                HStack(spacing: 14) {
                    Button(L10n.string("Continue Getting Started"), action: openGuide)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .accessibilityIdentifier("today.gettingStarted")
                    Text(L10n.string("%lld of %lld steps done", Int64(progress.completed), Int64(progress.total)))
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.secondaryInk)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(progress.completed)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    private func openGuide() {
        model.guideAnchor = .setUp
        model.selectedScreen = .gettingStarted
    }
}
