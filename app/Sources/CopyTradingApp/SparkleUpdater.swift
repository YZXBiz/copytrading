import Combine
import CopyTradingUI
import Foundation
import Sparkle

/// Updates through Sparkle: it reads the signed release feed (SUFeedURL), checks each download's
/// EdDSA signature against SUPublicEDKey, replaces the app, and relaunches it. A scheduled check
/// that finds an update shows the app's own banner (Sparkle's gentle reminders) instead of a
/// window; Install opens Sparkle's update window with the release notes.
@MainActor
@Observable
final class SparkleUpdater: AppUpdating {
    private let controller: SPUStandardUpdaterController
    private let delegate: UpdaterDelegate
    private var watching: AnyCancellable?
    private(set) var canCheckForUpdates = false
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
        watching = controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] canCheck in self?.canCheckForUpdates = canCheck }
    }

    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
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

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
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
