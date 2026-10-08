import SwiftUI

/// The guide's hero, set like a studio site's front page: a large headline, a two-line lede, the
/// walker on its ground heading for the next step, and the button that shows the owner around.
struct GuideHeader: View {
    let progress: SetupProgress
    /// Starts the setup tour on Connections.
    let startTour: () -> Void

    private var lede: (String, String) {
        progress.isComplete
            ? (L10n.string("You're set up."), L10n.string("This page stays here as your guide."))
            : (L10n.string("About 10 minutes, five steps."), L10n.string("Have your Discord, AI provider, and Alpaca logins at hand."))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.string("Getting started"))
                .font(DesignTokens.documentTitle)
                .tracking(DesignTokens.documentTitleTracking)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 6) {
                Text(lede.0)
                Text(lede.1)
            }
            .font(DesignTokens.lede)
            .tracking(DesignTokens.ledeTracking)
            .foregroundStyle(Palette.tertiaryInk)
            .multilineTextAlignment(.center)
            .padding(.top, 18)
            .accessibilityElement(children: .combine)
            if !progress.isComplete {
                Button(L10n.string(progress.completed == 0 ? "Show Me Around" : "Pick Up Where I Left Off"), action: startTour)
                    .buttonStyle(PageButtonStyle(isProminent: true, horizontalPadding: 18))
                    .padding(.top, 26)
                    .accessibilityIdentifier("guide.tour")
            }
            GuideStage(progress: progress)
                .padding(.top, 34)
        }
        .frame(maxWidth: .infinity)
    }
}
