import SwiftUI

/// The guide's title, with how far setup has come at
/// the trailing edge.
struct GuideHeader: View {
    let progress: SetupProgress
    /// Starts the setup tour on Connections.
    let startTour: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("Getting started 👋"))
                    .font(DesignTokens.documentTitle)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    progress.isComplete
                        ? L10n.string("You're set up. This page stays here as your guide.")
                        : L10n.string("About 10 minutes. Have your Discord, AI provider, and Alpaca logins at hand.")
                )
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.secondaryInk)
                if !progress.isComplete {
                    Button(
                        L10n.string(progress.completed == 0 ? "Show Me Around" : "Pick Up Where I Left Off"),
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath", action: startTour
                    )
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .padding(.top, 8)
                    .accessibilityIdentifier("guide.tour")
                }
            }
            Spacer(minLength: 16)
            HStack(spacing: 10) {
                Text(L10n.string("%lld of %lld", Int64(progress.completed), Int64(progress.total)))
                    .font(DesignTokens.caption.weight(.medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(progress.completed)))
                ProgressRing(progress: progress.fraction, size: 30)
            }
            .padding(.top, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.string("Setup progress, %lld of %lld steps done", Int64(progress.completed), Int64(progress.total)))
        }
    }
}
