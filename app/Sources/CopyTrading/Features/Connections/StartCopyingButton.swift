import SwiftUI

/// The one Start Copying: checks the setup, then saves it and starts copying when nothing needs
/// the owner. Live accounts ask first, from the button that asked.
struct StartCopyingButton: View {
    let model: AppModel
    @State private var confirmLiveStart = false

    var body: some View {
        Button(L10n.string("Start Copying"), systemImage: "play.fill", action: requestStart)
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStartCopyingFromCheck && !model.canCheckAndStart)
            .accessibilityIdentifier("setup.startCopying")
            .confirmationDialog(
                "Start copying into live accounts?",
                isPresented: $confirmLiveStart,
                titleVisibility: .visible
            ) {
                Button(L10n.string("Start Live Copying"), role: .destructive, action: start)
                Button(L10n.string("Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.string("Live accounts place real orders with real money. Copying starts only after this step."))
            }
    }

    private func requestStart() {
        if model.setupDraft.hasLiveAccounts {
            confirmLiveStart = true
        } else {
            start()
        }
    }

    private func start() {
        model.checkAndStartCopying()
    }
}
