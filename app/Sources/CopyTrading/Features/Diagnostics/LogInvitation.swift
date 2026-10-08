import SwiftUI

/// Diagnostics before anything is logged: what the log keeps, where it lives, and a way to see it
/// fill in, standing on the walker's ground.
struct LogInvitation: View {
    let model: AppModel

    private var engineRunning: Bool {
        model.runtimeState == .ready || model.runtimeState == .degraded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.string("The log starts here"))
                .font(DesignTokens.listHeading)
                .tracking(DesignTokens.listHeadingTracking)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            InkEmptyState(
                message: L10n.string(
                    "Posts, model calls, and trading steps appear here as the engine handles them, with keys removed. The log stays on this Mac."
                ))
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
                        .buttonStyle(PageButtonStyle(isProminent: true))
                        .disabled(!engineRunning || model.isRunningSelfTest)
                        .accessibilityIdentifier("diagnostics.runSelfTest")
                    Text(
                        engineRunning
                            ? L10n.string("A test message fills the log in a few seconds.")
                            : L10n.string("Start the engine and the log fills in as it works.")
                    )
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    private func runSelfTest() {
        Task { await model.runSelfTest() }
    }
}
