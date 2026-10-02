import SwiftUI

/// The Assistant menu: ⌘J opens the panel on any screen while CopyTrading is unlocked.
struct AssistantCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandMenu(L10n.string("Assistant")) {
            Button(L10n.string("Ask the Assistant")) { model.assistant.open() }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(!model.isTradingUnlocked)
        }
    }
}
