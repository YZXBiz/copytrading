import SwiftUI

/// "Check for Updates…" under the app menu, where Mac apps put it.
struct UpdateCommands: Commands {
    let updater: any AppUpdating

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(L10n.string("Check for Updates…"), action: updater.checkForUpdates)
                .disabled(!updater.canCheckForUpdates)
        }
    }
}
