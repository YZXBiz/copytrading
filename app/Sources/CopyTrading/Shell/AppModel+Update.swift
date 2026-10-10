import Foundation

extension AppModel {
    static let resumesAfterUpdateKey = "update.resumesCopying"

    /// Copying starts by itself at launch: the owner asked for it, or an update relaunched the
    /// app while it was copying.
    var wantsCopyingOnLaunch: Bool {
        launchPreferences.startsCopying || UserDefaults.standard.bool(forKey: Self.resumesAfterUpdateKey)
    }

    /// Just before an update relaunches the app: copying that runs now starts again after it.
    func rememberCopyingForRelaunch() {
        guard [.running, .degraded].contains(tradingStatus?.state) else { return }
        UserDefaults.standard.set(true, forKey: Self.resumesAfterUpdateKey)
    }

    /// What installing an update does to copying, said beside the offer.
    var updateCopyingNote: String? {
        guard [.running, .degraded].contains(tradingStatus?.state) else { return nil }
        return canStartCopyingOnLaunch
            ? L10n.string("Copying pauses while it installs and starts again when CopyTrading reopens.")
            : L10n.string("Copying stops while it installs. Start it again when CopyTrading reopens.")
    }
}
