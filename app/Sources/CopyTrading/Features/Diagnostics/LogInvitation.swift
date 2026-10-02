import SwiftUI

/// Diagnostics before anything is logged: what the log keeps, where it lives, and a way to see it
/// fill in.
struct LogInvitation: View {
    let model: AppModel

    private var engineRunning: Bool {
        model.runtimeState == .ready || model.runtimeState == .degraded
    }

    var body: some View {
        InvitationCard(
            lead: L10n.string("The log"),
            emphasis: L10n.string("starts here"),
            message: L10n.string(
                "Posts, model calls, and trading steps appear here as the engine handles them, with keys removed. The log stays on this Mac."
            )
        ) {
            LogInvitationFigure()
        } actions: {
            if model.isLoadingDiagnostics {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.string("Reading the log…"))
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.secondaryInk)
                }
            } else {
                HStack(spacing: 14) {
                    Button(L10n.string("Run Self-Test"), action: runSelfTest)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .disabled(!engineRunning || model.isRunningSelfTest)
                        .accessibilityIdentifier("diagnostics.runSelfTest")
                    Text(
                        engineRunning
                            ? L10n.string("A test message fills the log in a few seconds.")
                            : L10n.string("Start the engine and the log fills in as it works.")
                    )
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func runSelfTest() {
        Task { await model.runSelfTest() }
    }
}
