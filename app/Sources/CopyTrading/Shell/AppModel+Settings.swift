/// Settings opens over the workspace with a sidebar of its own: back through the
/// pages visited, and close to the screen it was opened from.
extension AppModel {
    func show(_ page: SettingsPage) {
        guard page != settingsPage else { return }
        settingsTrail.append(settingsPage)
        settingsPage = page
    }

    func settingsBack() {
        guard let page = settingsTrail.popLast() else { return }
        settingsPage = page
    }

    func closeSettings() {
        settingsTrail.removeAll()
        selectedScreen = screenBeforeSettings == .settings ? .today : screenBeforeSettings
    }
}
