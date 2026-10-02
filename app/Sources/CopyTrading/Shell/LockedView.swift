import SwiftUI

struct LockedView: View {
    let model: AppModel

    var body: some View {
        ContentUnavailableView {
            Label(L10n.string("CopyTrading is locked"), systemImage: "lock.shield")
        } description: {
            VStack(spacing: 8) {
                Text(L10n.string("Authenticate to view accounts, activity, settings, and local diagnostics."))
                if let runtimeStopMessage = model.runtimeStopMessage {
                    Text(runtimeStopMessage)
                }
                if let accessMessage = model.accessMessage {
                    Text(accessMessage)
                        .foregroundStyle(.orange)
                        .accessibilityLabel(L10n.string("Authentication status: %@", accessMessage))
                }
            }
        } actions: {
            if model.isUnlockingTrading {
                ProgressView(L10n.string("Waiting for macOS authentication…"))
            } else {
                Button(L10n.string("Unlock"), systemImage: "touchid", action: unlock)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("app.unlock")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func unlock() {
        Task { await model.unlockTrading() }
    }
}
