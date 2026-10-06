import CopyTradingUI
import Foundation
import SwiftUI

@main
@MainActor
struct CopyTradingApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var lifecycle
    @State private var updater = SparkleUpdater(starting: Self.startsUpdater)

    #if DEBUG
        /// UI journeys run a debug build on a throwaway state root; it looks for updates only when
        /// a test gives it a local feed.
        private static let startsUpdater =
            ProcessInfo.processInfo.environment["COPYTRADING_UI_TEST_UNLOCK"] != "1"
            || ProcessInfo.processInfo.environment["COPYTRADING_UPDATE_FEED"] != nil
    #else
        private static let startsUpdater = true
    #endif

    var body: some Scene {
        CopyTradingScene(lifecycle: lifecycle, updater: updater)
    }
}
