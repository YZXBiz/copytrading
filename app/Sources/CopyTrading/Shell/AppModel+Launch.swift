import DesktopCore

extension AppModel {
    static func makeForLaunch() -> AppModel {
        #if DEBUG
            if let unlock = UITestLaunch.appUnlock() {
                // UI journeys run on a throwaway root and keep launch preferences in memory.
                return AppModel(appUnlock: unlock)
            }
        #endif
        return AppModel(launchPreferencesStore: LaunchPreferencesStore(stateRoot: stateRoot))
    }
}
