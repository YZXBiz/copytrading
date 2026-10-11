import SwiftUI

/// File → Import Setup…: the same open panel as in Connections, from the menu bar.
struct SetupCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(L10n.string("Import Setup…")) {
                model.selectedScreen = .connections
                model.isShowingSetupImporter = true
            }
            .disabled(!model.isTradingUnlocked)
        }
    }
}
