import SwiftUI

/// ⌘1–⌘9 jump to the accounts, gurus and pages in sidebar order, ⌘K (or ⌘F) opens the palette,
/// and ⌘, opens Settings, whenever the app is unlocked.
struct GoCommands: Commands {
    @Bindable var model: AppModel

    private var numbered: [AppModel.Screen] {
        Array(model.navigableScreens.filter { $0 != .settings }.prefix(9))
    }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(L10n.string("Settings…")) { model.selectedScreen = .settings }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(!model.isTradingUnlocked)
        }
        CommandMenu(L10n.string("Go")) {
            Button(L10n.string("Find…")) { model.isShowingPalette.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(!model.isTradingUnlocked)
            Button(L10n.string("Find a Post…")) { model.isShowingPalette = true }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!model.isTradingUnlocked)
            Divider()
            ForEach(Array(numbered.enumerated()), id: \.element) { index, screen in
                Button(model.title(of: screen)) { model.selectedScreen = screen }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .disabled(!model.isTradingUnlocked)
            }
        }
    }
}
