import SwiftUI

/// Diagnostics before anything is logged: one line on the ink dot's ground, and a way to see the
/// log fill in.
struct LogInvitation: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            InkEmptyState(message: L10n.string("Nothing logged yet"))
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
                        .buttonStyle(PageButtonStyle(emphasis: .prominent))
                        .disabled(!model.isEngineRunning || model.isRunningSelfTest)
                        .accessibilityIdentifier("diagnostics.runSelfTest")
                    Text(
                        model.isEngineRunning
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
