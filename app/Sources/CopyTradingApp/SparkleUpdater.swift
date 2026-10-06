import Combine
import CopyTradingUI
import Foundation
import Sparkle

/// Updates through Sparkle: it reads the signed release feed (SUFeedURL), checks each download's
/// EdDSA signature against SUPublicEDKey, replaces the app, and relaunches it.
@MainActor
@Observable
final class SparkleUpdater: AppUpdating {
    private let controller: SPUStandardUpdaterController
    private var watching: AnyCancellable?
    private(set) var canCheckForUpdates = false

    #if DEBUG
        /// Debug builds can read a local feed (COPYTRADING_UPDATE_FEED) to test an update end to
        /// end; release builds read only SUFeedURL.
        private let feed = LocalFeed()
    #endif

    init(starting: Bool) {
        #if DEBUG
            controller = SPUStandardUpdaterController(
                startingUpdater: starting, updaterDelegate: feed, userDriverDelegate: nil)
        #else
            controller = SPUStandardUpdaterController(
                startingUpdater: starting, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
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
}

#if DEBUG
    private final class LocalFeed: NSObject, SPUUpdaterDelegate {
        func feedURLString(for updater: SPUUpdater) -> String? {
            ProcessInfo.processInfo.environment["COPYTRADING_UPDATE_FEED"]
        }
    }
#endif
