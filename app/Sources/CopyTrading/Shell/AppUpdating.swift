import SwiftUI

/// Checking for and installing a newer CopyTrading. The app's entry point supplies Sparkle; the
/// screens see only this, so they build and preview without it (ADR-0009).
@MainActor
public protocol AppUpdating: AnyObject {
    /// False while a check is already running, so the button cannot start a second one.
    var canCheckForUpdates: Bool { get }
    var checksAutomatically: Bool { get set }
    func checkForUpdates()
    /// A newer version found by a scheduled check, which the banner offers.
    var offer: UpdateOffer { get }
    /// Shows the update to install it: release notes, then Install and Relaunch.
    func installOfferedUpdate()
    /// Runs just before the updater quits the app to relaunch it.
    var willRelaunch: (@MainActor () -> Void)? { get set }
}

/// Previews and tests: nothing to check.
@MainActor
final class NoUpdates: AppUpdating {
    var canCheckForUpdates: Bool { false }
    var checksAutomatically = false
    func checkForUpdates() {}
    let offer = UpdateOffer()
    func installOfferedUpdate() {}
    var willRelaunch: (@MainActor () -> Void)?
}
