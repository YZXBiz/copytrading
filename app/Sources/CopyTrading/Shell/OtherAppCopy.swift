import AppKit

/// Another copy of CopyTrading, such as an installed one beside a local build, shares this one's
/// data folder, and only one engine can hold it.
enum OtherAppCopy {
    /// Another running app with this app's identifier, if there is one.
    @MainActor
    static var running: NSRunningApplication? {
        guard let identifier = Bundle.main.bundleIdentifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first { $0.processIdentifier != me && !$0.isTerminated }
    }
}
