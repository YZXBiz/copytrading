import SwiftUI

/// ⌘1–⌘6 jump between screens in sidebar order and ⌘, opens Settings, whenever the app is unlocked.
struct GoCommands: Commands {
    @Bindable var model: AppModel

    private var numbered: [AppModel.Screen] {
        AppModel.ScreenSection.allCases.flatMap(\.screens).filter { $0 != .settings }
    }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(L10n.string("Settings…")) { model.selectedScreen = .settings }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(!model.isTradingUnlocked)
        }
        CommandMenu(L10n.string("Go")) {
            ForEach(Array(numbered.enumerated()), id: \.element) { index, screen in
                Button(L10n.string(screen.title)) { model.selectedScreen = screen }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .disabled(!model.isTradingUnlocked)
            }
        }
    }
}
