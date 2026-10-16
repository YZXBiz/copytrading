import Combine
import CopyTradingUI
import DesktopCore
import Foundation
import Sparkle

/// Updates through Sparkle: it reads the signed release feed (SUFeedURL), checks each download's
/// EdDSA signature against SUPublicEDKey, replaces the app, and relaunches it. A scheduled check
/// that finds an update shows the app's own banner (Sparkle's gentle reminders) instead of a
/// window; Install opens Sparkle's update window with the release notes. An app in a folder macOS
/// guards is never quit for an install that can't land there, and an install that fails after
/// the app quit still ends with the app open again (RelaunchGuard).
@MainActor
@Observable
final class SparkleUpdater: AppUpdating {
    private let controller: SPUStandardUpdaterController
    private let delegate: UpdaterDelegate
    private var watching: Set<AnyCancellable> = []
    private(set) var canCheckForUpdates = false
    /// Sparkle's setting mirrored here, so the switch redraws when it changes.
    private var automaticChecks = false
    let offer = UpdateOffer()
    var willRelaunch: (@MainActor () -> Void)? {
        get { delegate.willRelaunch }
        set { delegate.willRelaunch = newValue }
    }

    init(starting: Bool) {
        delegate = UpdaterDelegate(offer: offer)
        controller = SPUStandardUpdaterController(
            startingUpdater: starting, updaterDelegate: delegate, userDriverDelegate: delegate)
        // As Sparkle's SwiftUI example does; the updater reports on the main thread.
        controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] canCheck in self?.canCheckForUpdates = canCheck }
            .store(in: &watching)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] checks in self?.automaticChecks = checks }
            .store(in: &watching)
    }

    var checksAutomatically: Bool {
        get { automaticChecks }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Sparkle's gentle-reminder flow: checking again brings the found update into focus.
    func installOfferedUpdate() {
        controller.checkForUpdates(nil)
    }
}

@MainActor
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    let offer: UpdateOffer
    var willRelaunch: (@MainActor () -> Void)?
    /// A version a scheduled check found while the app sits in a guarded folder, offered with
    /// that folder once Sparkle ends the check.
    private var blocked: (version: String, folder: ProtectedFolder)?

    init(offer: UpdateOffer) {
        self.offer = offer
    }

    #if DEBUG
        /// Debug builds can read a local feed (COPYTRADING_UPDATE_FEED) to test an update end to
        /// end; release builds read only SUFeedURL.
        func feedURLString(for updater: SPUUpdater) -> String? {
            ProcessInfo.processInfo.environment["COPYTRADING_UPDATE_FEED"]
        }
    #endif

    /// Sparkle's installer can't replace the app in a folder macOS guards: macOS stops it to ask
    /// after the app has quit, and nothing reopens the app. So the update stops here, while the
    /// app still runs, and says to move the app.
    func updater(
        _ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck
    ) throws {
        guard let folder = ProtectedFolder.containing(Bundle.main.bundleURL) else { return }
        if updateCheck == .updatesInBackground {
            blocked = (updateItem.displayVersionString, folder)
        }
        throw NSError(
            domain: "dev.copytrading.update", code: 1,
            userInfo: [NSLocalizedDescriptionKey: folder.updateRefusal])
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        guard let blocked else { return }
        self.blocked = nil
        offer.found(blocked.version, blockedIn: blocked.folder.name)
    }

    /// Sparkle quits the app next. If its installer then fails, it never reopens the app, so the
    /// guard does.
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        if let executable = Bundle.main.executableURL {
            _ = try? RelaunchGuard.start(appPID: getpid(), executable: executable, bundle: Bundle.main.bundleURL)
        }
        willRelaunch?()
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Scheduled checks never open a window over the owner's work; the banner offers them.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate {
            offer.found(update.displayVersionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        offer.withdraw()
    }

    func standardUserDriverWillFinishUpdateSession() {
        offer.withdraw()
    }
}
