import AppKit
import CopyTradingUI

/// The app's `NSApplication`, made in main.swift before SwiftUI starts. Every way of quitting
/// reaches `terminate(_:)`; the lifecycle delegate answers first, so a sheet never stops a quit.
@objc(CopyTradingApplication)
final class CopyTradingApplication: NSApplication {
    override func terminate(_ sender: Any?) {
        AppLifecycleDelegate.requestQuit { super.terminate(sender) }
    }
}
